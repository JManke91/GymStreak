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
3. If "Update template" was chosen, calls
   `RoutineTemplateSyncService.applyPerformedValues(from:reconcileExerciseMembership: false)`.
   Then `save()` — one save either way, since the service mutates but never saves.
4. `fetchWorkoutHistory()`; invalidates the stale AI cache for the session
   (`AICoachCache.invalidatePostWorkout` + `invalidateWorkoutAnalysis`).
5. If the template changed, posts `.routineTemplateDidChange`.

### Template update + set-count reconcile
`RoutineTemplateSyncService.applyPerformedValues(from:reconcileExerciseMembership:)`
(`Domain/Services/`, extracted from `WorkoutViewModel` by audit P1.5) is shared with
`completeWorkout`. It pushes reps/weight from completed sets and rest time onto the matching
`RoutineExercise`, and **reconciles set count**: surplus template sets are deleted and extra
session sets are appended, so add/delete edits are reflected for future workouts. (This count
reconciliation also applies to the active-workout completion path — an intentional consistency
improvement.)

`reconcileExerciseMembership` is what separates the two callers: `completeWorkout` passes `true`
and may add or remove routine slots, this path passes `false` and never does — a routine may have
changed since that older workout was recorded. `false` is also the only mode that enables the
legacy fallback in slot matching (resolving by exercise id/name when history predates slot ids),
and only when *no* workout exercise carries a slot id.

### Regression coverage

Before P1.5 this whole path had **no** tests — nothing in the repo called `saveEditedWorkout`.
Two suites now cover it:

- `RoutineTemplateSyncServiceTests` — the template writeback the ViewModel delegates to:
  value writeback, never adding/removing slots, the legacy id/name fallback, mixed history
  disabling that fallback, set-count reconciliation, and that the service does not save.
- `EditWorkoutSessionCommitTests` — what the ViewModel itself does: editing a kept set writes
  the actual fields (planned when `usePlanned`), a dropped draft set deletes its `WorkoutSet`,
  an added set is inserted in draft order seeding both field pairs, unmarking a set clears
  `completedAt`, a draft for an unknown exercise is skipped, `didUpdateTemplate` and the
  `.routineTemplateDidChange` post fire only when the template was updated, and
  `historyVersion` advances.

**Latent bug fixed by P1.5, pinned by
`editsToARoutinelessWorkoutSurviveEvenWhenTemplateUpdateIsRequested`:** the template writeback
used to own the only `save()` on the `updateTemplate == true` branch, and it returns early for a
session with no routine — so ticking "update routine" on a routine-less workout silently
**discarded the user's set edits**. The save is now unconditional. The test was verified to fail
against the old control flow before being kept.

*Not covered:* the two `AICoachCache` invalidations — there is no `AICoachCaching` double in the
test target and the real `.shared` does `FileManager` I/O in the test host. That is audit P2.6.

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
| `GymStreak/Presentation/ViewModels/WorkoutViewModel.swift` | `saveEditedWorkout` (draft commit, cache invalidation, notification) |
| `GymStreak/Domain/Services/RoutineTemplateSyncService.swift` | `applyPerformedValues(from:reconcileExerciseMembership:)` — the template writeback + set-count reconcile |
| `GymStreak/Presentation/Views/History/WorkoutDetailView.swift` | Ellipsis toolbar menu (Edit + Delete), sheet presentation, post-edit reload |
| `GymStreak/Presentation/ViewModels/RoutinesViewModel.swift` | `observeRoutineTemplateChanges()` → re-fetch + watch sync |
| `GymStreak/Data/Sync/WatchConnectivityManager.swift` | `Notification.Name.routineTemplateDidChange` |
| `GymStreak/Presentation/Views/Workout/SetInputComponents.swift` | Reused `HorizontalStepper` / `WeightInput` |
| `GymStreak/Resources/{en,de}.lproj/Localizable.strings` | `edit_workout.*` strings |
