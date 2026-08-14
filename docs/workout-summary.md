# Workout Summary Screens

## Overview

Workout summary screens provide users with a quick review of their completed workout on both iOS and watchOS.

## iOS: SaveWorkoutView

**File**: `GymStreak/SaveWorkoutView.swift`

### What it shows
- **Duration**: Formatted workout time
- **Sets**: Combined format showing `completed/total (percentage%)` — green text at 100%
- **Est. Calories**: Based on duration (4.5 kcal/minute for strength training)
- **Exercise Progress**: Per-slot volume change compared to the previous workout of the same routine exercise; repeated heavy/high-rep uses remain separate
  - Volume increase: green arrow with percentage
  - Volume decrease: orange arrow with percentage
  - First time: tint-colored "New" badge
- **HealthKit toggle**: Option to sync to Apple Health
- **Template update toggle**: Option to update routine template with actual values
- **Notes**: Optional workout notes

### How exercise progress works
Uses `ExerciseProgressService.compareWithPrevious(workout:)` (`async`) which:
1. Identifies the exercise by `exerciseId`, keeping same-name equipment variants separate
2. Selects the same `routineExerciseId` programming slot so repeated uses do not cross-compare
3. For legacy history without slot ids, matches the ordered occurrence only when the stable routine relationship proves the same routine; missing or ambiguous identity produces no comparison
4. Computes `volumeDeltaPercentage` = `((currentVolume - previousVolume) / previousVolume) * 100`
5. Returns `ExerciseComparisonResult` with comparison data, each row carrying its `workoutExerciseId`

**Where each step runs (audit P1.6, 2026-08-14).** Steps 1–3 are the history scan and
happen inside `SwiftDataHistorySnapshotStore`'s `@ModelActor` via
`PreviousPerformanceResolver`, behind a `@concurrent` boundary; steps 4–5 read only the
workout being saved and stay on the main actor via `ExerciseComparisonBuilder`. That split
is deliberate: this screen appears before the user commits the workout, and a model actor
cannot be trusted to see a session the main context has not saved. The service itself holds
no `ModelContext` — see [progress-charts.md](./progress-charts.md) for the full rationale
and the 213 ms measurement. It is loaded via the `.task` modifier on the view.

Before that change it ran fully synchronously on the main actor, issuing one unbounded
unprefetched fetch **per exercise**, so finishing a workout froze the app for the duration.

### Architecture
- `SaveWorkoutView` uses `@Environment(\.modelContext)` to access SwiftData
- `ExerciseImprovementRow` (private struct) renders each exercise's progress indicator
- Reuses `DeltaBadge` from `Views/Components/DeltaBadge.swift`

## watchOS: WatchWorkoutSummaryView

**File**: `GymStreakWatch Watch App/Views/WatchWorkoutSummaryView.swift`

### What it shows
- **Header**: Checkmark icon, "Workout Complete" title, routine name
- **Stats card**: Duration, sets (completed/total with percentage), calories (from HealthKit)
- **Exercises card**: Per-exercise completion status with checkmark (complete) or minus badge (partial)
- **Done button**: Dismisses the summary and returns to routine list

### Data flow
1. User taps "End Workout" on watch `ControlsView`
2. Confirmation dialog appears (save options + discard)
3. On save: `WatchWorkoutViewModel.endWorkout()` is called
4. **Before** ending the HealthKit session, `generateWorkoutSummary()` captures all metrics into `WatchWorkoutSummary`
5. HealthKit session ends, data syncs to iPhone
6. `ActiveWorkoutView` detects `viewModel.workoutSummary != nil` and shows `WatchWorkoutSummaryView`
7. User taps "Done" -> `dismissSummary()` clears summary and resets state -> `dismiss()` returns to routine list
8. "Discard" bypasses summary entirely and dismisses immediately

### Why summary is captured before ending HealthKit
After `healthKitManager.endWorkout()`, HealthKit metrics (elapsed time, calories, heart rate) stop updating. The summary must snapshot these values before the session ends.

### No historical comparison on watch
The watch does not have SwiftData/ModelContext and cannot access workout history. Exercise progress comparison is only available on iOS.

### Design system usage
- Colors: `OnyxWatch.Colors` (black bg, card gray, tint green, textOnTint black)
- Typography: `.watchHeader`, `.watchCaption`, `.watchNumber`, `.watchNumberSmall`
- Spacing: `OnyxWatch.Spacing` (xs/sm/md/lg/xl)
- Cards: `RoundedRectangle` with `cornerRadiusMD` and `OnyxWatch.Colors.card` fill
- Button: `.borderedProminent` with tint color
- Haptics: `.success` on appear

## Key Models

### WatchWorkoutSummary (`WatchModels.swift`)
```swift
struct WatchWorkoutSummary {
    let routineName: String
    let duration: TimeInterval
    let completedSets: Int
    let totalSets: Int
    let completionPercentage: Int
    let activeCalories: Int?
    let exercises: [ExerciseSummary]
}
```

### ExerciseComparisonResult (`ExerciseProgressModels.swift`)
Used by iOS `SaveWorkoutView` for exercise progress display. Contains `volumeDeltaPercentage` and `isFirstTime` flags.

## Files involved

| File | Target | Role |
|------|--------|------|
| `SaveWorkoutView.swift` | iOS | Post-workout save form with summary |
| `Views/Components/DeltaBadge.swift` | iOS | Reusable delta indicator component |
| `Data/Progress/ExerciseProgressService.swift` | iOS | The comparison seam: pure builders either side of one off-main history call |
| `Domain/Services/ExerciseComparisonBuilder.swift` | iOS | Reduces the current workout to a lookup, then assembles the comparison rows (main actor) |
| `Domain/Services/PreviousPerformanceResolver.swift` | iOS | Resolves each exercise against its previous session (model actor) |
| `Domain/Models/PreviousPerformanceLookup.swift` | iOS | `Sendable` request carrying the workout across the actor boundary |
| `Domain/Models/ExerciseProgressModels.swift` | iOS | Comparison result data structures |
| `WatchWorkoutSummaryView.swift` | watchOS | Post-workout summary view |
| `WatchModels.swift` | watchOS | WatchWorkoutSummary struct |
| `WatchWorkoutViewModel.swift` | watchOS | Summary generation and state management |
| `ActiveWorkoutView.swift` | watchOS | Flow control (workout tabs vs summary) |
