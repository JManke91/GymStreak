# Watch ↔ iOS Routine Sync

## Overview
The GymStreak app syncs workout routine templates between iOS and watchOS using WatchConnectivity. iOS is the source of truth (SwiftData + CloudKit), while the watch maintains a lightweight local cache (UserDefaults via App Group).

## Architecture

### Data Flow

```
iOS (SwiftData + CloudKit)
  ↓ updateApplicationContext([WatchRoutine] as JSON)
Watch (RoutineStore → UserDefaults)
  ↓ transferUserInfo(CompletedWatchWorkout)
iOS (processes workout, updates template, syncs back)
```

### iOS Target
- **Persistence**: SwiftData `ModelContainer` with CloudKit (`iCloud.com.jmanke.gymstreak`)
- **Sync trigger**: `RoutinesViewModel.fetchRoutines()` calls `syncRoutinesToWatch()` after every fetch
- **Receives workouts**: `WatchConnectivityManager.didReceiveUserInfo` → notification → `RoutinesViewModel.handleCompletedWatchWorkout()`

### watchOS Target
- **Persistence**: `RoutineStore` saves `[WatchRoutine]` as JSON in App Group UserDefaults (`group.com.gymstreak.shared`)
- **Receives routines**: `WatchConnectivityManager.didReceiveApplicationContext` → `RoutineStore.updateRoutines()`
- **No SwiftData/CloudKit**: Watch uses lightweight Codable structs only

## Sync Methods

| Direction | Method | Behavior |
|-----------|--------|----------|
| iOS → Watch | `updateApplicationContext` | Coalesced (only latest delivered), guaranteed delivery |
| Watch → iOS | `transferUserInfo` | Queued FIFO, guaranteed delivery, wakes iOS in background |
| iOS → Watch (fallback) | `sendMessage` | Real-time only, requires reachability |

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
| `GymStreak/WatchConnectivityManager.swift` | WCSession management, sends routines, receives workouts |
| `GymStreak/RoutinesViewModel.swift` | Processes watch workouts, updates templates, triggers sync |
| `GymStreak/WatchModels.swift` | Shared Codable structs + `Routine.toWatchRoutine()` conversion |
| `GymStreak/CloudSyncObserver.swift` | Observes CloudKit remote changes, triggers refetch |

### watchOS Target
| File | Role |
|------|------|
| `GymStreakWatch/Managers/WatchConnectivityManager.swift` | Receives routines, sends completed workouts |
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
