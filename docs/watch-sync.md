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
  ↑ persists CompletedWatchWorkout to App Group; kept until iOS acks the save; retried on activation/reachability
iOS (buffers to App Group, dedupes, saves WorkoutSession, posts .workoutHistoryDidChange, acks watch)
  ↓ acknowledgeWorkoutSaved (workoutAck) — watch clears its pending queue only now
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
| Watch → iOS (guaranteed) | `transferUserInfo` | Queued FIFO. Does NOT background-launch iOS — payload sits until user opens iOS app. `didFinish` success ≠ app receipt, so the watch keeps its copy until iOS sends an app-level ack |
| iOS → Watch (save ack) | `acknowledgeWorkoutSaved` → `sendMessage` + `transferUserInfo` | Confirms the WorkoutSession was committed to SwiftData; the watch removes the workout from its pending queue only on this ack |
| iOS → Watch (fallback) | `sendMessage` | Real-time only, requires reachability |

## Reliability Architecture (Watch → iOS Workout Sync)

This path historically had silent-loss failure modes (workouts saved to HealthKit but never appearing in iOS history). The current architecture defends against them in five layers:

1. **Persist before transfer (watch)**: `WatchConnectivityManager.sendCompletedWorkout` writes the `CompletedWatchWorkout` to App Group UserDefaults BEFORE calling `transferUserInfo`. If the watch app suspends before the OS commits the transfer to its persistent queue, the workout is recovered on next launch.

2. **Dual-path send (watch)**: When iOS is reachable, `sendMessage` is fired alongside `transferUserInfo` — the former delivers instantly to a foregrounded iOS app; the latter guarantees eventual delivery. Both paths converge through iOS-side dedupe.

3. **App-level save acknowledgment (watch ↔ iOS) — the critical fix.** The watch does **NOT** clear a workout from its pending queue when `WCSessionDelegate.session(_:didFinish:error:)` reports a successful transfer. That callback only confirms WatchConnectivity delivered the payload to the paired device's WC *daemon* — it does **not** guarantee the iOS *app* ever received or persisted it (the app may be force-quit, mid-launch after a reboot, or the transfer may be superseded). Clearing on `didFinish` was the historical root cause of "saved to HealthKit but never in iOS history": once cleared, the watch had no copy left to retry, and re-opening the watch did nothing.

   Instead, the watch keeps the workout queued until iOS sends an explicit **app-level ack** confirming the `WorkoutSession` was committed to SwiftData. After saving (or detecting a duplicate), `RoutinesViewModel.handleCompletedWatchWorkout` calls `WatchConnectivityManager.acknowledgeWorkoutSaved(id:)`, which sends `{"workoutAck": <id>}` over both `sendMessage` (fast path) and `transferUserInfo` (guaranteed). The watch's `handleIncoming` removes the workout from the pending queue on receipt. Because iOS re-acks on every duplicate it sees and the watch retries on every activation/reachability change, delivery is self-healing: any single lost ack or transfer converges. Transfer *failures* (error != nil) also leave the entry queued for retry.

4. **Persist on receipt (iOS)**: `WatchConnectivityManager.handleIncomingPayload` writes incoming workouts to a separate App Group key (`pendingReceivedWorkouts`) before posting `.watchWorkoutCompleted`. If the app crashes between WC delivery and SwiftData save, the buffer is replayed on next activation.

5. **Idempotent ingest (iOS)**: `RoutinesViewModel.handleCompletedWatchWorkout` checks for an existing `WorkoutSession` by `id` (preserved from the watch payload) or `healthKitWorkoutId` before inserting. Duplicate deliveries from `sendMessage` + `transferUserInfo` or from watch-side retries are safely skipped. The buffer entry is removed via `WatchConnectivityManager.markPendingProcessed(id:)` and the watch is re-acked, on either a successful save or a dedupe.

6. **HealthKit reconciliation + recovery safety net (iOS)**: `HealthKitWorkoutReconciler` queries HKWorkout for any workout authored by GymStreak (matching the bundle prefix `com.shotat24fps.GymStreak`) within the last 30 days. For each workout it reads `HKMetadataKeyExternalUUID`, `RoutineName`/`HKMetadataKeyWorkoutBrandName`, and `RoutineId`, and compares the external UUID against the set of `WorkoutSession.healthKitWorkoutId` values already in SwiftData. Any HKWorkout with no matching record is surfaced as a `PendingSyncBannerView` on the History tab. The reconciler runs on `WorkoutViewModel.updateModelContext` (HistoryView `onAppear`), on `.workoutHistoryDidChange`, and when `scenePhase` becomes `.active`.

   The reconciler does **not** gate on `HKHealthStore.authorizationStatus(for:)` — that API reports *write* (sharing) status only and says nothing about reads; HealthKit always returns samples the app wrote itself. Gating on `.sharingAuthorized` previously suppressed both detection and recovery for users who hadn't granted write access on iOS.

   **Recovery (user-confirmed reconstruction).** This is the path for the residual cases where the watch genuinely can no longer redeliver — app reinstalled, unpaired/repaired, or an old workout that predates the ack handshake. The banner exposes an **"Add to history"** button. On confirmation, `WorkoutViewModel.recoverOrphanedWorkouts()` rebuilds a `WorkoutSession` for each orphan: it matches the routine by `RoutineId` (exact) or name, reconstructs the exercises/sets from that routine template (planned values used as actuals, since HKWorkout lacks per-set detail), stamps the HKWorkout's start/end/duration and external UUID onto the session, and notes it as *Recovered from Apple Health*. Setting `healthKitWorkoutId` to the external UUID means the reconciler no longer flags it. If no routine matches, a summary-only session is created (no phantom routine is persisted — the denormalized `routineName` drives display).

After a successful save, `RoutinesViewModel` posts `.workoutHistoryDidChange`. `WorkoutViewModel` (used by `HistoryView`) observes this and refreshes its cached `workoutHistory` AND re-runs the reconciler, so the new workout appears without requiring the user to leave and re-enter the History tab.

## Template Update Flow

When a user modifies set values during a watch workout and chooses "Save & Update Template":

1. **Watch local update** (immediate): `WatchWorkoutViewModel.endWorkout()` calls `RoutineStore.applyWorkoutChanges()` to update the local routine store instantly
2. **Sync to iOS**: `transferUserInfo` sends `CompletedWatchWorkout` with `shouldUpdateTemplate: true`
3. **iOS processing**: `RoutinesViewModel.handleCompletedWatchWorkout()` creates `WorkoutSession` history and updates SwiftData `Routine` template
4. **Sync back to watch**: `updateRoutine()` → `fetchRoutines()` → `syncRoutinesToWatch()` sends updated routines via `applicationContext`

The watch self-update (step 1) ensures the user sees updated template values immediately for the next workout, without waiting for the iOS round-trip.

### Trigger: editing a past workout (iOS)
The template can also change when a user edits a completed workout in History and chooses "Update
template" (see `docs/edit-past-workout.md`). In that case `WorkoutViewModel.saveEditedWorkout` updates
the SwiftData `Routine` and posts `.routineTemplateDidChange`. `RoutinesViewModel` observes this
(`observeRoutineTemplateChanges()`) and calls `fetchRoutines()` → `syncRoutinesToWatch()`, so the
corrected template reaches the watch through the standard `applicationContext` path. No watch-target
code is involved.

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
