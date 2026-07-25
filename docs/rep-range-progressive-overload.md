# Rep Range Goal & Progressive Overload

> **Note (2026-07):** The Routines tab was visually redesigned (see [routines-exercises-redesign.md](./routines-exercises-redesign.md)). Rep-range/overload logic is unchanged; `ExerciseHeaderView` and `RoutineSetRowView` now live in `RoutineDetailComponents.swift`. The rep-range goal is also surfaced as a "Ziel %d–%d Wdh." info chip on each exercise card.

## Feature Description

Adds a **rep range goal** (e.g., 8-12 reps) to exercises within routines. When all sets reach the upper limit, the app celebrates and suggests a weight increase with options to auto-apply (new weight + reset reps to lower limit). This implements the "Double Progression" model - the industry-standard approach for progressive overload.

## User Flow

1. **Configure**: In routine editor, tap "Set Rep Goal" on any exercise to set a min/max range (e.g., 8-12)
2. **Train**: During workouts, rep progress badges show how close each set is to the upper limit
3. **Achieve**: When all sets reach the upper limit, a gold banner appears suggesting a weight increase
4. **Progress**: Tap "Increase" to open the weight increase sheet, select an increment (1.25/2.5/5 kg), and apply
5. **Reset**: All sets update to the new weight with reps reset to the lower limit
6. **Second chance (completion screen)**: If the mid-workout banner was skipped or dismissed, the post-workout completion screen (`SaveWorkoutView`) shows an actionable "Ready for More Weight" card per qualifying exercise — same increment sheet, same apply path — with an Undo while the screen is still open
7. **After the fact (history)**: Opening a past session in `WorkoutDetailView` re-surfaces the same card for any exercise that maxed its rep range. Applying here bumps the **live routine template only** for future workouts — it never rewrites the immutable history — so there is no Undo. If the routine/exercise no longer exists, the achievement still shows but the CTA becomes a muted no-op note

## Architecture

### Shared Domain Logic — `ProgressiveOverloadService`

**`Domain/Services/ProgressiveOverloadService.swift`** (added 2026-07) is the single source of truth for the overload domain logic. It is pure value math (Foundation only — no SwiftData/SwiftUI), so future surfaces (completion screen, history, watch — the watch target gets its own file copy per the project's target-sharing convention) apply identical rules:

- `templateQualifiesForIncrease(reps:targetRepMax:)` — routine editor qualify: every template set's reps ≥ max (no completion concept)
- `workoutQualifiesForIncrease(sets:targetRepMax:overloadAlreadyApplied:)` — workout qualify: all sets completed AND actual reps ≥ max; `overloadAlreadyApplied` short-circuits to `true`
- `increasedWeight(_:increment:loadBehavior:)` — direction-aware weight step: counterweight assistance *subtracts* the increment (clamped at 0), resistance adds it
- `applyIncrease(toWeights:increment:targetRepMin:loadBehavior:)` — returns the new weight per set + the reps every set resets to (range minimum)

The model computed properties (`RoutineExercise.allSetsAtUpperLimit`, `WorkoutExercise.allCompletedSetsAtUpperLimit`) and both ViewModels delegate to this service; no qualify/apply math is duplicated anywhere else. Covered by `GymStreakTests/ProgressiveOverloadServiceTests.swift` (Swift Testing).

**Root cause fixed during consolidation:** `RoutinesViewModel.applyProgressiveOverload` previously always did `weight += increment`, even for counterweight-assistance exercises — while `WeightIncreaseSheet` displayed "−increment" and `WorkoutViewModel` correctly subtracted. Applying an increase from the **routine editor** on an assistance exercise therefore *raised* the assistance weight (making the exercise easier) despite the sheet promising a reduction. The shared service's direction-aware math now applies in both paths. The same +only math also existed in `ActiveWorkoutView`'s post-apply confirmation chip (display only); it now uses `increasedWeight` too.

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
- Both `allSetsAtUpperLimit` (RoutineExercise) and `allCompletedSetsAtUpperLimit` (WorkoutExercise) delegate to `ProgressiveOverloadService` — the properties are thin adapters mapping model sets to plain values

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
- `applyProgressiveOverload(for:weightIncrement:)` - Increases weight and resets reps to min for all sets, via `ProgressiveOverloadService.applyIncrease`

**`WorkoutViewModel`**:
- `applyProgressiveOverload(for:weightIncrement:)` - Gets the new weights/reps from `ProgressiveOverloadService.applyIncrease` (for both the live workout sets and the routine template), and owns the persistence workflow around it: planned-value snapshotting, setting `progressiveOverloadApplied`, and saving. Also captures an in-memory pre-apply snapshot (per-set planned/actual values + template set values) keyed by `WorkoutExercise.id` to power Undo
- `routineExercise(for:)` - Resolves the routine-template slot a `WorkoutExercise` originated from, swapped or not: matches by `routineExerciseId` (stable slot identity) first, falls back to the originally-planned exercise id/name for legacy data (mirroring `updateRoutineTemplate`)
- `performedExercise(for:)` / private `alternativeEntry(for:)` - For a swapped exercise, resolve the performed alternative's library `Exercise` and its `RoutineExerciseAlternative` entry. **Swap rule (2026-07 fix):** applying overload on a swapped exercise writes into the *alternative's own set scheme* (`AlternativeExerciseSet`), never the primary slot's sets — the same rule `updateRoutineTemplate` follows. Before this fix the whole overload path was dead for swaps: the mid-workout banner resolved the slot by performed-exercise name, which never matches the primary, so "Increase" was a silent no-op
- `overloadSuggestionExercises` - The completion screen's eligibility list: rep goal maxed AND (already applied OR a persistable template target exists — the slot's sets, or the alternative's set scheme for swaps)
- `undoProgressiveOverload(for:)` / `canUndoProgressiveOverload(for:)` - Reverts an overload applied during this session from the completion screen: restores the sets' pre-apply planned/actual values, clears `progressiveOverloadApplied`, and restores the template's set scheme. Snapshots are in-memory only and cleared when the session ends (save or discard), so undo is available exactly while the completion screen can still be shown
- `applyProgressiveOverloadFromHistory(from:for:weightIncrement:)` - The **history (after-the-fact)** apply path. Resolves the live template from the *completed session's* `routine` (not `currentSession`) via the routine-parameterized `routineExercise(in:for:)`/`alternativeEntry(in:for:)`, bumps the slot's sets (or the swapped alternative's set scheme) through `ProgressiveOverloadService.applyIncrease`, and returns the new weight. **Never touches the historical `WorkoutExercise`/`WorkoutSet` or the `progressiveOverloadApplied` flag** — history is immutable. Returns `nil` (no-op) if the routine/exercise was edited/deleted. `hasResolvableOverloadTemplate(from:for:)` and `performedExercise(in:for:)` are its resolution/display companions. The generic `applyOverloadToTemplateSets(_:weightKey:repsKey:…)` bumps either template set type (`ExerciseSet`, `AlternativeExerciseSet`) via key paths, avoiding duplicated increment/reset math

## Components

### iOS Components

| Component | File | Description |
|-----------|------|-------------|
| `RepRangeConfigView` | Views/Components/RepRangeConfigView.swift | Collapsible config with min/max steppers and presets (Strength/Hypertrophy/Endurance) |
| `ProgressiveOverloadBanner` | Views/Components/ProgressiveOverloadBanner.swift | Gold/orange banner shown when all sets reach upper limit |
| `WeightIncreaseSheet` | Views/Components/WeightIncreaseSheet.swift | Bottom sheet for selecting weight increment (+1.25/+2.5/+5 kg). Value-based with two inits: `init(routineExercise:)` shows template values (routine editor), `init(workoutExercise:)` shows performed actual values (active workout + completion screen — correct for swapped exercises, whose weights never live on the primary template sets) |
| `ProgressiveOverloadCard` | Views/Components/ProgressiveOverloadCard.swift | Achievement card (from the Claude Design "Progressive Overload" handoff, Surface 1): orange actionable state with per-set recap + full-width increase CTA, and a quiet confirmed state with the new weight and Undo. Reuses `ExerciseAvatarView` (muscle color + equipment glyph — the app's avatar idiom, deliberately not the mock's initials). Set recap hides at accessibility Dynamic Type sizes; title + action always stay visible. Shared by the completion screen and history: history-only params (`appliedOverride`/`appliedWeight` force the confirmed state and supply its weight because the immutable history can't be read for it; `isTemplateUnavailable` swaps the CTA for the muted no-op note) default to the completion-screen behavior |

### Integration Points

| View | Integration |
|------|-------------|
| `RoutineDetailView` | RepRangeConfigView + ProgressiveOverloadBanner + rep progress badges on sets |
| `ExerciseHeaderView` | Subtitle shows "3 sets \| 8-12 reps" when configured |
| `RoutineSetRowView` | Rep count colored by range position + "X/max" badge |
| `ActiveWorkoutView` | Rep progress badges on sets + ProgressiveOverloadBanner |
| `SaveWorkoutView` | "Ready for More Weight" section: one `ProgressiveOverloadCard` per exercise in `WorkoutViewModel.overloadSuggestionExercises` (replaced the passive trophy section 2026-07), section header shows a pending-suggestion counter (orange; turns green once one was applied). Applying opens `WeightIncreaseSheet(workoutExercise:)` and calls `WorkoutViewModel.applyProgressiveOverload`; exercises overloaded mid-workout appear in their confirmed state. No persistable template target (slot or alternative entry) → no CTA |
| `WorkoutDetailView` | "Ready for More Weight" section (after the stat grid): one `ProgressiveOverloadCard` per exercise whose completed sets maxed the rep range — re-surfacing the achievement the history redesign dropped. Applying opens `WeightIncreaseSheet(workoutExercise:)` and calls `WorkoutViewModel.applyProgressiveOverloadFromHistory`, which bumps the **live routine template only** — the historical `WorkoutExercise`/`WorkoutSet` are never rewritten. Applied state (and the shown new weight) is tracked in view-local `@State` since the immutable history can't hold it; no Undo. Exercises overloaded during that workout show their confirmed state directly. If the source routine/exercise was edited/deleted, the card keeps the achievement but replaces the CTA with a muted "routine no longer available" note (`rep_range.overload_card.routine_unavailable`) |

### Watch Integration

| View | Integration |
|------|-------------|
| `WatchWorkoutSummaryView` | Trophy icon next to exercises that achieved rep goal |

`targetRepMin`/`targetRepMax` still ride along in the watch payload
(`WatchModels.swift`), but **no watch view renders them** since 2026-07-25: the
only rep-range goal text + color coding lived in the unused legacy
`ExerciseSetView`, which was deleted with the rest of the dead watch views. The
live set screen (`FullScreenSetEditorView`) never had it. Recover the old
rendering from git history if the goal indicator is wanted on watch.

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

The completion screen's apply path is the **same** `applyProgressiveOverload` call, so applying there never rewrites the session's history either — the just-performed reps/weights survive in `plannedReps`/`plannedWeight` via the identical snapshot. Undo (completion screen only) restores both the session sets' pre-apply planned/actual values and the template's set scheme (the alternative's for swapped exercises) from the in-memory snapshot; it is intentionally unavailable after the session ends.

**Root cause fixed (2026-07, swapped exercises):** every overload surface used to resolve the template slot by comparing the *performed* exercise name against slot primaries (`exercise?.name == workoutExercise.exerciseName`). For a swapped exercise the names never match, so the mid-workout banner's "Increase" silently did nothing (nil sheet item) and the mid-workout template write no-opped. Resolution now goes through `WorkoutViewModel.routineExercise(for:)` (stable `routineExerciseId`, then planned-exercise fallback) and swapped exercises persist into the alternative's own set scheme. Do not reintroduce name-based slot matching against performed names.

## Localization

All user-facing strings are localized in both English and German via `Localizable.strings`. Keys are prefixed with `rep_range.*` (card copy under `rep_range.overload_card.*` — including `rep_range.overload_card.routine_unavailable` for the history no-op note — plus `rep_range.ready_for_more` and `action.undo`). The card's description/confirmation strings embed `**bold**` markdown markers that `ProgressiveOverloadCard` parses and colors with the accent (orange/green) — keep the markers when editing translations.
