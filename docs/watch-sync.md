# Watch ↔ iOS Routine Sync

## Overview
The GymStreak app syncs workout routine templates between iOS and watchOS using WatchConnectivity. iOS is the source of truth (SwiftData + CloudKit), while the watch maintains a lightweight local cache (UserDefaults via App Group).

## Architecture

### Data Flow

```
iOS (SwiftData + CloudKit)
  ↓ updateApplicationContext([WatchRoutine] as JSON)
Watch (RoutineStore → UserDefaults)
  ↓ sendMessage (fast path, when reachable) + transferUserInfo (always, guaranteed delivery)
  ↑ also persists CompletedWatchWorkout to App Group; retried on activation/reachability change
iOS (buffers to App Group, dedupes, saves WorkoutSession, posts .workoutHistoryDidChange)
```

### iOS Target
- **Persistence**: SwiftData `ModelContainer` with CloudKit (`iCloud.com.jmanke.gymstreak`)
- **Sync trigger**: `RoutinesViewModel.fetchRoutines()` calls `syncRoutinesToWatch()` after every fetch
- **WC bootstrap**: `WatchConnectivityManager.shared` is bound as a `@StateObject` on `GymStreakApp` so the WCSession delegate is registered before any view appears (avoids cold-start activation race)
- **Receives workouts**: `WatchConnectivityManager.didReceiveUserInfo` AND `didReceiveMessage` (fast path) → buffer to App Group → notification → `RoutinesViewModel.handleCompletedWatchWorkout()`
- **Pending buffer**: `group.com.gymstreak.shared` UserDefaults key `pendingReceivedWorkouts` — survives crashes between WC delivery and SwiftData save

### watchOS Target
- **Persistence**: `RoutineStore` saves `[WatchRoutine]` as JSON in App Group UserDefaults (`group.com.gymstreak.shared`)
- **Receives routines**: `WatchConnectivityManager.didReceiveApplicationContext` → `RoutineStore.updateRoutines()`
- **No SwiftData/CloudKit**: Watch uses lightweight Codable structs only
- **Pending send queue**: `group.com.gymstreak.shared` UserDefaults key `pendingCompletedWorkouts` — workouts persist here until `didFinishUserInfoTransfer` confirms delivery; retried on activation and reachability changes

## Sync Methods

| Direction | Method | Behavior |
|-----------|--------|----------|
| iOS → Watch | `updateApplicationContext` | Coalesced (only latest delivered), guaranteed delivery |
| Watch → iOS (fast) | `sendMessage` | Real-time, requires reachability — fired alongside transferUserInfo for immediate UI updates |
| Watch → Watch→iOS (guaranteed) | `transferUserInfo` | Queued FIFO. Note: does NOT background-launch iOS — payload sits until user opens iOS app |
| iOS → Watch (fallback) | `sendMessage` | Real-time only, requires reachability |

## Reliability Architecture (Watch → iOS Workout Sync)

This path historically had silent-loss failure modes (workouts saved to HealthKit but never appearing in iOS history). The current architecture defends against them in five layers:

1. **Persist before transfer (watch)**: `WatchConnectivityManager.sendCompletedWorkout` writes the `CompletedWatchWorkout` to App Group UserDefaults BEFORE calling `transferUserInfo`. If the watch app suspends before the OS commits the transfer to its persistent queue, the workout is recovered on next launch.

2. **Dual-path send (watch)**: When iOS is reachable, `sendMessage` is fired alongside `transferUserInfo` — the former delivers instantly to a foregrounded iOS app; the latter guarantees eventual delivery. Both paths converge through iOS-side dedupe.

3. **Transfer confirmation (watch)**: `WCSessionDelegate.session(_:didFinish:error:)` removes the workout from the pending queue ONLY after the OS confirms the transfer. Failures leave the entry in place for retry on the next activation or reachability change.

4. **Persist on receipt (iOS)**: `WatchConnectivityManager.handleIncomingPayload` writes incoming workouts to a separate App Group key (`pendingReceivedWorkouts`) before posting `.watchWorkoutCompleted`. If the app crashes between WC delivery and SwiftData save, the buffer is replayed on next activation.

5. **Idempotent ingest (iOS)**: `RoutinesViewModel.handleCompletedWatchWorkout` checks for an existing `WorkoutSession` by `id` (preserved from the watch payload) or `healthKitWorkoutId` before inserting. Duplicate deliveries from `sendMessage` + `transferUserInfo` or from watch-side retries are safely skipped. The buffer entry is removed via `WatchConnectivityManager.markPendingProcessed(id:)` only after a successful save or dedupe.

6. **HealthKit reconciliation safety net (iOS)**: `HealthKitWorkoutReconciler` queries HKWorkout for any workout authored by GymStreak (matching the bundle prefix `com.shotat24fps.GymStreak`) within the last 30 days. For each workout, it reads `HKMetadataKeyExternalUUID` and compares against the set of `WorkoutSession.healthKitWorkoutId` values already in SwiftData. Any HKWorkout with no matching SwiftData record is surfaced as a `PendingSyncBannerView` on the History tab. The reconciler runs on `WorkoutViewModel.updateModelContext` (triggered by HistoryView's `onAppear`), on `.workoutHistoryDidChange`, and when the app's `scenePhase` becomes `.active`. The banner does not auto-create stub sessions — HKWorkout lacks per-set rep/weight detail — but it tells the user the workout was recorded, and prompts them to re-open GymStreak on their watch so the persistent retry queue can redeliver the rich payload.

After a successful save, `RoutinesViewModel` posts `.workoutHistoryDidChange`. `WorkoutViewModel` (used by `HistoryView`) observes this and refreshes its cached `workoutHistory` AND re-runs the reconciler, so the new workout appears without requiring the user to leave and re-enter the History tab.

## Template Update Flow

When a user modifies set values during a watch workout and chooses "Save & Update Template":

1. **Watch local update** (immediate): `WatchWorkoutViewModel.endWorkout()` calls `RoutineStore.applyWorkoutChanges()` to update the local routine store instantly
2. **Sync to iOS**: `transferUserInfo` sends `CompletedWatchWorkout` with `shouldUpdateTemplate: true`
3. **iOS processing**: `RoutinesViewModel.handleCompletedWatchWorkout()` creates `WorkoutSession` history and updates SwiftData `Routine` template
4. **Sync back to watch**: `updateRoutine()` → `fetchRoutines()` → `syncRoutinesToWatch()` sends updated routines via `applicationContext`

The watch self-update (step 1) ensures the user sees updated template values immediately for the next workout, without waiting for the iOS round-trip.

### iOS Init Order
`RoutinesViewModel.init()` processes pending watch workouts BEFORE the first `fetchRoutines()` call. This prevents sending stale routine data to the watch when the iOS app launches with an unprocessed pending workout:

```
observeWatchWorkoutCompletions() → processPendingWatchWorkouts() → fetchRoutines()
```

## Key Files

### iOS Target
| File | Role |
|------|------|
| `GymStreak/GymStreakApp.swift` | Bootstraps `WatchConnectivityManager.shared` at App init via `@StateObject` |
| `GymStreak/WatchConnectivityManager.swift` | WCSession management, dual-path receive (userInfo + message), persistent receive buffer |
| `GymStreak/RoutinesViewModel.swift` | Idempotent ingest, drains pending buffer on init, posts `.workoutHistoryDidChange` |
| `GymStreak/WorkoutViewModel.swift` | Observes `.workoutHistoryDidChange`, refreshes cached history, runs HK reconciler |
| `GymStreak/Services/HealthKitWorkoutReconciler.swift` | Queries HKWorkout for orphans (no matching SwiftData record) — safety-net layer |
| `GymStreak/Views/History/Components/PendingSyncBannerView.swift` | Banner shown on History tab when orphans exist |
| `GymStreak/WatchModels.swift` | Shared Codable structs + `Routine.toWatchRoutine()` conversion |
| `GymStreak/CloudSyncObserver.swift` | Observes CloudKit remote changes, triggers refetch |

### watchOS Target
| File | Role |
|------|------|
| `GymStreakWatch/Managers/WatchConnectivityManager.swift` | Receives routines, sends completed workouts with persistent retry queue, `didFinishUserInfoTransfer` confirmation |
| `GymStreakWatch/Managers/RoutineStore.swift` | Local persistence, applies workout changes |
| `GymStreakWatch/ViewModels/WatchWorkoutViewModel.swift` | Workout lifecycle, local template update |
| `GymStreakWatch/Models/WatchModels.swift` | All watch data models + conversion extensions |
| `GymStreakWatch/Views/WatchWorkoutSummaryView.swift` | Post-workout summary with template update banner |

## Lightweight Models

- `WatchRoutine` / `WatchExercise` / `WatchSet`: Template data (Codable, Hashable)
- `ActiveWorkoutExercise` / `ActiveWorkoutSet`: In-memory workout state with planned vs actual values
- `CompletedWatchWorkout` / `CompletedWatchExercise` / `CompletedWatchSet`: Completed workout data sent to iOS

All models preserve UUIDs from the iOS SwiftData originals for ID-based matching when updating templates.

## UI Feedback
When a template is updated on the watch, a "Template updated" banner appears on the workout summary screen (`WatchWorkoutSummaryView`), driven by `WatchWorkoutViewModel.templateWasUpdated`.
