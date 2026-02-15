# Watch ↔ iOS Sync Architecture

## Overview
The GymStreak app syncs workout routine templates between iOS and watchOS using **SwiftData + CloudKit**. Both platforms share the same iCloud container (`iCloud.com.jmanke.gymstreak`) and SwiftData schema, making CloudKit the primary sync mechanism for routine templates.

WatchConnectivity is retained **only** for delivering completed workout data (Watch → iOS) to create `WorkoutSession` history records.

## Architecture

### Data Flow

```
iOS (SwiftData + CloudKit) ←→ iCloud ←→ Watch (SwiftData + CloudKit)
                                              ↓
                                        transferUserInfo(CompletedWatchWorkout)
                                              ↓
                                    iOS (creates WorkoutSession history)
```

### Shared SwiftData Models
Both targets compile the same `Models.swift` (via symlink in `GymStreakWatch Watch App/Shared/`):
- `Routine`, `Exercise`, `RoutineExercise`, `ExerciseSet`
- `WorkoutSession`, `WorkoutExercise`, `WorkoutSet`

### iOS Target
- **Persistence**: SwiftData `ModelContainer` with CloudKit (`iCloud.com.jmanke.gymstreak`)
- **Routine management**: Full CRUD via `RoutinesViewModel` — changes sync to watch via CloudKit automatically
- **Receives workouts**: `WatchConnectivityManager.didReceiveUserInfo` → notification → `RoutinesViewModel.handleCompletedWatchWorkout()` (creates `WorkoutSession` only, no template update)

### watchOS Target
- **Persistence**: SwiftData `ModelContainer` with CloudKit (same container as iOS)
- **Routine display**: `@Query` in views fetches routines directly from SwiftData
- **Template updates**: `WatchWorkoutViewModel` writes modified set values directly to SwiftData; CloudKit syncs to iOS automatically
- **CloudSyncObserver**: Observes `NSPersistentStoreRemoteChange` to trigger UI refresh when CloudKit syncs new data from iOS

## Sync Methods

| Direction | Method | What syncs |
|-----------|--------|------------|
| iOS ↔ Watch | CloudKit (automatic) | Routine templates, exercises, sets |
| Watch → iOS | `transferUserInfo` | Completed workout data for history |

## Template Update Flow

When a user modifies set values during a watch workout and chooses "Save & Update Template":

1. **Watch SwiftData update** (immediate): `WatchWorkoutViewModel.endWorkout()` calls `applyTemplateUpdate()` which modifies `RoutineExercise`/`ExerciseSet` records directly via `ModelContext`
2. **CloudKit sync** (automatic): SwiftData syncs the changes to iCloud, which pushes to iOS
3. **iOS receives sync**: `CloudSyncObserver` detects remote change → `RoutinesViewModel.fetchRoutines()` refreshes local state
4. **Completed workout delivery**: `transferUserInfo` sends `CompletedWatchWorkout` to iOS for `WorkoutSession` history creation

This architecture avoids CloudKit conflicts — the watch owns template updates from workouts, while iOS owns template updates from the routines editor. Both write to the same SwiftData store, and CloudKit handles merge.

## Key Files

### iOS Target
| File | Role |
|------|------|
| `GymStreak/WatchConnectivityManager.swift` | WCSession management, receives completed workouts |
| `GymStreak/RoutinesViewModel.swift` | Processes watch workouts into history, routine CRUD |
| `GymStreak/WatchModels.swift` | `CompletedWatchWorkout` DTO types |
| `GymStreak/CloudSyncObserver.swift` | Observes CloudKit remote changes, triggers refetch |
| `GymStreak/Models.swift` | Shared SwiftData models |

### watchOS Target
| File | Role |
|------|------|
| `GymStreakWatch/Shared/Models.swift` | Symlink to shared SwiftData models |
| `GymStreakWatch/Shared/CloudSyncObserver.swift` | Symlink to shared CloudKit observer |
| `GymStreakWatch/Managers/WatchConnectivityManager.swift` | Sends completed workouts to iOS |
| `GymStreakWatch/ViewModels/WatchWorkoutViewModel.swift` | Workout lifecycle, direct SwiftData template update |
| `GymStreakWatch/Models/WatchModels.swift` | Active workout state, completed workout DTOs, conversion extensions |
| `GymStreakWatch/Views/RoutineListView.swift` | `@Query`-driven routine list |
| `GymStreakWatch/Views/RoutineDetailView.swift` | Routine preview using `Routine` model |

## Data Models

### Shared (SwiftData, synced via CloudKit)
- `Routine` / `RoutineExercise` / `ExerciseSet`: Template data
- `WorkoutSession` / `WorkoutExercise` / `WorkoutSet`: Workout history

### Watch-only (in-memory, not persisted)
- `ActiveWorkoutExercise` / `ActiveWorkoutSet`: Runtime workout state with planned vs actual values
- `WatchWorkoutSummary`: Post-workout summary display

### DTO (Codable, sent via WatchConnectivity)
- `CompletedWatchWorkout` / `CompletedWatchExercise` / `CompletedWatchSet`: Completed workout data sent to iOS

All SwiftData models preserve UUIDs across devices, enabling ID-based matching.

## UI Feedback
When a template is updated on the watch, a "Template updated" banner appears on the workout summary screen (`WatchWorkoutSummaryView`), driven by `WatchWorkoutViewModel.templateWasUpdated`.

## Required Entitlements & Capabilities

CloudKit uses **silent push notifications (APNs)** to notify devices when records change in iCloud. Both targets must have the following configured for sync to work:

| Capability | iOS Target | watchOS Target | Purpose |
|------------|-----------|----------------|---------|
| Push Notifications (`aps-environment`) | Required | Required | Receive silent pushes when CloudKit records change |
| Remote Notifications background mode | Required | Required | Process incoming CloudKit change notifications in the background |
| iCloud (CloudKit) | Required | Required | Access to shared `iCloud.com.jmanke.gymstreak` container |

**Foreground sync nudge**: The watch app also performs a lightweight SwiftData fetch when it becomes active (`scenePhase == .active`) via `WatchRootView`. This handles cases where silent push notifications were missed (e.g., the watch was offline or the app wasn't running).

> **Note**: If the watch target is missing push notification entitlements, CloudKit data will only sync when the app launches — not in the background. This can cause routines created on iPhone to appear missing on the watch until the user manually opens the watch app.

## Debugging & Logging

All sync-related code uses `os.Logger` (visible in Console.app when debugging over USB). No `print()` statements remain in sync paths.

### Logger Subsystems & Categories

| Subsystem | Category | File(s) | What it logs |
|-----------|----------|---------|--------------|
| `com.jmanke.gymstreak` | `CloudSync` | `CloudSyncObserver.swift` | Remote change notifications, sync version, store identifier |
| `com.jmanke.gymstreak` | `RoutinesSync` | `RoutinesViewModel.swift` | CloudKit-triggered refetches, routine counts before/after, save results, watch workout processing |
| `com.jmanke.gymstreak` | `ExercisesSync` | `ExercisesViewModel.swift` | CloudKit-triggered refetches, exercise counts before/after |
| `com.jmanke.gymstreak` | `WorkoutSync` | `WorkoutViewModel.swift` | CloudKit-triggered workout history refreshes |
| `com.jmanke.gymstreak` | `WatchConnectivity` | `WatchConnectivityManager.swift` (iOS) | Session activation, reachability, workout receipt |
| `com.jmanke.gymstreak` | `App` | `GymStreakApp.swift` | Container initialization errors |
| `com.jmanke.gymstreak.watch` | `App` | `GymStreakWatchApp.swift` | Container initialization, foreground sync nudge |
| `com.jmanke.gymstreak.watch` | `WatchConnectivity` | `WatchConnectivityManager.swift` (Watch) | Session activation, workout sends |
| `com.jmanke.gymstreak.watch` | `Workout` | `WatchWorkoutViewModel.swift` | Template updates via SwiftData, save success/failure |
| `com.jmanke.gymstreak.watch` | `RoutineList` | `RoutineListView.swift` | `@Query` routine count changes |

### Tracing a Sync Event (iPhone → Watch)

1. **iPhone**: `[RoutinesSync]` "Fetched routines: N" — routine created/modified
2. **iCloud**: CloudKit syncs record automatically
3. **Watch**: `[CloudSync]` "Remote change detected from CloudKit (syncVersion: N, store: ...)"
4. **Watch**: `[RoutineList]` "Routine list updated — now showing N routines"

### Extra Debugging

For verbose framework-level CloudKit logging, add launch argument: `-com.apple.CoreData.CloudKitDebug 1` (values 1-3 for increasing verbosity).

## Simulator Limitations

CloudKit sync **cannot** be tested on simulators:
- **watchOS simulator**: Does not support CloudKit at all (throws "Not Authenticated" errors)
- **iOS simulator**: Partial CloudKit support but cannot receive push notifications, so automatic sync doesn't trigger
- **Physical devices required**: All sync testing must use a real iPhone + Apple Watch, both signed into the same iCloud account
- **TestFlight**: Uses the production CloudKit environment — ensure the schema is deployed to production before distributing TestFlight builds

## Offline Behavior
- **Watch offline**: Template updates are saved locally to SwiftData. CloudKit syncs when connectivity is restored.
- **No iCloud account**: Both platforms fall back to local-only SwiftData storage. Watch still functions fully for workouts; completed workouts still sync via WatchConnectivity.
