# Rep Range Goal & Progressive Overload

## Feature Description

Adds a **rep range goal** (e.g., 8-12 reps) to exercises within routines. When all sets reach the upper limit, the app celebrates and suggests a weight increase with options to auto-apply (new weight + reset reps to lower limit). This implements the "Double Progression" model - the industry-standard approach for progressive overload.

## User Flow

1. **Configure**: In routine editor, tap "Set Rep Goal" on any exercise to set a min/max range (e.g., 8-12)
2. **Train**: During workouts, rep progress badges show how close each set is to the upper limit
3. **Achieve**: When all sets reach the upper limit, a gold banner appears suggesting a weight increase
4. **Progress**: Tap "Increase" to open the weight increase sheet, select an increment (1.25/2.5/5 kg), and apply
5. **Reset**: All sets update to the new weight with reps reset to the lower limit

## Architecture

### Data Model

**`RoutineExercise`** (Models.swift):
- `targetRepMin: Int?` - Lower bound of rep range (e.g., 8)
- `targetRepMax: Int?` - Upper bound of rep range (e.g., 12)
- `hasRepRangeGoal: Bool` - Computed: both fields non-nil
- `allSetsAtUpperLimit: Bool` - Computed: all sets at/above max reps

**`WorkoutExercise`** (Models.swift):
- `targetRepMin: Int?` / `targetRepMax: Int?` - Denormalized from RoutineExercise at workout creation
- `progressiveOverloadApplied: Bool` - Flag set when progressive overload is applied during a workout
- `hasRepRangeGoal: Bool` / `allCompletedSetsAtUpperLimit: Bool` - Computed properties
- `allCompletedSetsAtUpperLimit` returns `true` immediately when `progressiveOverloadApplied` is set (the user already hit the upper limit to trigger overload)

**Design decisions:**
- Optional `Int?` fields with nil defaults for seamless CloudKit/SwiftData lightweight migration
- Rep range on `RoutineExercise` (not `Exercise`) so different routines can use different ranges
- Denormalized to `WorkoutExercise` so history shows the range active at workout time
- When progressive overload is applied, `plannedWeight`/`plannedReps` on `WorkoutSet` are snapshotted from the current `actualWeight`/`actualReps` to preserve the user's actual performance. `actualWeight`/`actualReps` are then updated to the new overloaded values (for UI). All comparison/history/chart logic uses planned values when this flag is set.

### Watch Models

**WatchExercise** / **CompletedWatchExercise** / **ActiveWorkoutExercise** (WatchModels.swift on both targets):
- `targetRepMin: Int?` / `targetRepMax: Int?` added to all exercise structs
- Backward compatible: optional Codable fields default to nil when absent in JSON
- `ActiveWorkoutExercise` gains `hasRepRangeGoal` and `allCompletedSetsAtUpperLimit` computed properties
- `ExerciseSummary` gains `repGoalAchieved: Bool` for watch workout summary

### ViewModel

**`RoutinesViewModel`**:
- `updateRepRange(for:min:max:)` - Sets/clears rep range on a RoutineExercise
- `applyProgressiveOverload(for:weightIncrement:)` - Increases weight and resets reps to min for all sets

## Components

### iOS Components

| Component | File | Description |
|-----------|------|-------------|
| `RepRangeConfigView` | Views/Components/RepRangeConfigView.swift | Collapsible config with min/max steppers and presets (Strength/Hypertrophy/Endurance) |
| `ProgressiveOverloadBanner` | Views/Components/ProgressiveOverloadBanner.swift | Gold/orange banner shown when all sets reach upper limit |
| `WeightIncreaseSheet` | Views/Components/WeightIncreaseSheet.swift | Bottom sheet for selecting weight increment (+1.25/+2.5/+5 kg) |

### Integration Points

| View | Integration |
|------|-------------|
| `RoutineDetailView` | RepRangeConfigView + ProgressiveOverloadBanner + rep progress badges on sets |
| `ExerciseHeaderView` | Subtitle shows "3 sets \| 8-12 reps" when configured |
| `RoutineSetRowView` | Rep count colored by range position + "X/max" badge |
| `ActiveWorkoutView` | Rep progress badges on sets + ProgressiveOverloadBanner |
| `SaveWorkoutView` | "Rep Goal Achieved" section with trophy badges |
| `WorkoutDetailView` | Trophy badge on exercises + rep-range-colored set rows |

### Watch Integration

| View | Integration |
|------|-------------|
| `ExerciseSetView` | Rep range goal text below reps + color coding |
| `WatchWorkoutSummaryView` | Trophy icon next to exercises that achieved rep goal |

## Color Scheme

| State | Color | Meaning |
|-------|-------|---------|
| Below min | `.secondary` | Not yet in target range |
| In range (min to max-1) | `DesignSystem.Colors.tint` (green) | Working within target |
| At upper limit (>= max) | `.orange` | Achievement / ready to progress |

## Patterns Reused

- `RestTimerConfigView` pattern for `RepRangeConfigView` (collapsible config with presets)
- `ApplyToAllBanner` pattern for `ProgressiveOverloadBanner` (contextual action banner)
- `HorizontalStepper` for min/max rep inputs
- Superset denormalization pattern for rep range fields in `WorkoutExercise`
- Per-exercise state dictionaries (`[UUID: Bool]`) for expansion/dismissal tracking

## Progressive Overload Data Integrity

When `applyProgressiveOverload` is called during a workout:

1. **`WorkoutSet.plannedWeight/plannedReps`** are snapshotted from `actualWeight/actualReps` — preserving the user's actual performance before overload
2. **`WorkoutSet.actualWeight/actualReps`** are then updated to the new overloaded values (higher weight, min reps) for UI display
3. **`WorkoutExercise.progressiveOverloadApplied`** is set to `true`
4. **Routine template** (`ExerciseSet`) is updated with the new weight/reps for future workouts

The following services check `progressiveOverloadApplied` and use planned values when set:
- `ExerciseProgressService.fetchProgressData()` — chart data points
- `ExerciseProgressService.previousPerformance()` — historical lookup for comparison
- `ExerciseProgressService.compareWithPrevious()` — summary/detail comparison
- `WorkoutSession.totalVolume` — session volume calculation

This ensures the summary screen, workout detail view, and progress charts all show the user's actual performance rather than the overloaded values.

## Localization

All user-facing strings are localized in both English and German via `Localizable.strings`. Keys are prefixed with `rep_range.*`.
