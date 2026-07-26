# Edit a Past Workout

## Overview
Users can edit a completed workout from the **History (Verlauf) → workout detail** screen
(`WorkoutDetailView`). Previously this screen was read-only, so a mistracked set (wrong reps/weight,
missed completion, an extra or missing set) could not be corrected after finishing. The edit flow lets
users fix the recorded values and, optionally, push those corrections back to the routine template so
the next workout — on **both iOS and Apple Watch** — starts from the corrected plan.

This mirrors the active-workout "Save & update template" flow (`SaveWorkoutView` →
`WorkoutViewModel.completeWorkout`).

**Entry point (updated 2026-07-26):** Edit is no longer a standalone pencil button. The detail screen's
trailing toolbar item is now an ellipsis `Menu` holding **Edit Workout** and a destructive **Delete**;
Edit presents the same `EditWorkoutSessionView` sheet as before. See [Delete a Recorded
Workout](./delete-workout.md).

**Targets:** iOS only. The watch needs **no code changes** — it receives the updated routine through the
existing `applicationContext` routine-sync path (see `docs/watch-sync.md`).

## What can be edited
Per set within each exercise of the session:
- Reps (`HorizontalStepper`)
- Weight (`WeightInput`, 0.25 kg increments)
- Completion (`Toggle`) — affects volume / intensity / sets stats and PR computation
- Rest time (`Slider`, 0–300 s, 30 s steps)
- Add a set (copies the last set's values) / delete a set (swipe)

Exercises themselves are not added or removed in this flow.

## How it works

### Draft / commit / cancel pattern
Editing mutates **value-type drafts**, never the live SwiftData `@Model` objects, until the user taps
Save. This is the approach recommended by the iOS API research: `modelContext.rollback()` /
`undoManager` are context-wide and unreliable with CloudKit (and not configured in this app), so a
draft snapshot is the clean way to support Cancel.

- `WorkoutSetDraft` — `id`, `existingSetId` (`nil` ⇒ newly added), `reps`, `weight`, `restTime`,
  `isCompleted`.
- `WorkoutExerciseDraft` — `id` (the `WorkoutExercise.id`), `name`, `usePlanned`, `sets`.

`EditWorkoutSessionView.buildDrafts()` snapshots the session on appear. It captures the **displayed**
values: when `WorkoutExercise.progressiveOverloadApplied` is true the planned fields are shown/edited
(matching `WorkoutDetailExerciseBlock`'s `usePlanned`), otherwise the actual fields.

- **Cancel** simply dismisses — drafts are discarded, the model is untouched.
- **Save** calls `WorkoutViewModel.saveEditedWorkout(_:exerciseDrafts:updateTemplate:)`.

### Commit
`WorkoutViewModel.saveEditedWorkout`:
1. For each exercise draft, deletes `WorkoutSet`s absent from the draft, updates kept sets (writing back
   to planned or actual per `usePlanned`, syncing `isCompleted`/`completedAt`, reassigning `order`), and
   inserts newly added sets.
2. Sets `session.didUpdateTemplate`.
3. If "Update template" was chosen, calls `updateRoutineTemplate(session:)`; otherwise `save()`.
4. `fetchWorkoutHistory()`; invalidates the stale AI cache for the session
   (`AICoachCache.invalidatePostWorkout` + `invalidateWorkoutAnalysis`).
5. If the template changed, posts `.routineTemplateDidChange`.

### Template update + set-count reconcile
`updateRoutineTemplate(session:)` is shared with `completeWorkout`. It pushes reps/weight from completed
sets and rest time onto the matching `RoutineExercise`, and now **reconciles set count**: surplus
template sets are deleted and extra session sets are appended, so add/delete edits are reflected for
future workouts. (This count reconciliation also applies to the active-workout completion path — an
intentional consistency improvement.)

### Watch propagation
`saveEditedWorkout` posts `.routineTemplateDidChange` (declared in `WatchConnectivityManager.swift`).
`RoutinesViewModel.observeRoutineTemplateChanges()` observes it and calls `fetchRoutines()`, which runs
the existing `syncRoutinesToWatch()` → `watchConnectivity.syncRoutines(routines)`. The watch applies the
updated template via `RoutineStore.updateRoutines`. No watch-target changes are required.

### Detail refresh
`WorkoutDetailView` presents the editor via `.sheet(isPresented:onDismiss:)`. The set grid is
`@Model`-observed and updates automatically; on dismiss `reloadAfterEdit()` re-runs `loadPRs()`,
`loadComparisons()` and `loadCoachState()` so PR badges and vs-previous deltas reflect the edits.

## Edge cases
- **No routine (recovered/orphaned sessions):** `WorkoutSession.routine == nil`, so the editor saves
  directly with no template prompt.
- **Progressive overload:** values are read/written from the planned fields (the displayed values). The
  template update keeps the existing semantics (reps/weight from completed sets' actual values).
- **HealthKit:** editing reps/weight requires **no** HealthKit change — HK only ever stored the
  workout's duration and energy, never per-set reps/weight. `healthKitWorkoutId` is untouched.

## Key files
| File | Role |
|------|------|
| `GymStreak/Presentation/Views/History/EditWorkoutSessionView.swift` | Draft editor sheet + draft structs |
| `GymStreak/Presentation/ViewModels/WorkoutViewModel.swift` | `saveEditedWorkout`, reconciling `updateRoutineTemplate` |
| `GymStreak/Presentation/Views/History/WorkoutDetailView.swift` | Ellipsis toolbar menu (Edit + Delete), sheet presentation, post-edit reload |
| `GymStreak/Presentation/ViewModels/RoutinesViewModel.swift` | `observeRoutineTemplateChanges()` → re-fetch + watch sync |
| `GymStreak/Data/Sync/WatchConnectivityManager.swift` | `Notification.Name.routineTemplateDidChange` |
| `GymStreak/Presentation/Views/Workout/SetInputComponents.swift` | Reused `HorizontalStepper` / `WeightInput` |
| `GymStreak/Resources/{en,de}.lproj/Localizable.strings` | `edit_workout.*` strings |
