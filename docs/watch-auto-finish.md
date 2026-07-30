# Watch — Auto-finish on final set

## Overview
On the Apple Watch, completing the **last remaining incomplete set anywhere in the
routine** now finishes the workout end-to-end automatically. The user no longer has
to navigate back to the exercise list and press "Finish" after their last set. The
completing tap marks the set done, plays the "Done" celebration flash, ends the
HealthKit session, sends the completed workout to iPhone, and surfaces
`WatchWorkoutSummaryView`.

Target: **watchOS only** (`GymStreakWatch Watch App`). No iOS changes.

Source: Things todo `NLwNAjjdS6jjDoniuhSR87` (Gym Streak → Bugs). Local slice
`.scratch/watch-auto-finish-last-set/issues/01-auto-finish-on-final-set.md`.

## How it works
Detection and the finish trigger live in the shared completion path in
`WatchWorkoutViewModel.applyToggleSetCompletion(_:)`. Immediately after a set is
marked complete (`r.newState == true`) and the success haptic plays, the view model
checks `findNextIncompleteSet()`:

- **Returns nil** (zero incomplete sets remain anywhere) → call `autoFinishWorkout()`
  and `return` early, *before* any rest timer is started or the cursor advances. This
  avoids a stray rest-timer overlay flashing on the finishing tap.
- **Returns a set** → unchanged behavior: start the rest timer (superset-round-aware)
  and advance to the next incomplete set.

**Progressive-overload interaction (ticket 04, 2026-07-27).** The same mutation now
also decides whether the completed exercise qualifies for a mid-workout weight
increase — computed *before* auto-advance, against the slot that was just
completed, so navigation can never lose the slot identity:

- **Final set AND qualifying** → the delayed auto-finish is cancelled
  (`cancelAutoFinishForOverloadFlow()`) and the suggestion capsule opens instead of
  the workout finishing underneath it. Apply or "Later" re-enters the one
  `autoFinishWorkout()` path **exactly once**; no second, unretained finish task is
  ever created.
- **Non-final and qualifying** → the rest timer starts and the cursor advances as
  usual, and the suggestion is raised *afterwards*. Order matters: `startRestTimer`
  resets `isRestTimerMinimized`, so raising the suggestion first would let the
  full-screen rest overlay cover it. The timer keeps running; only its overlay is
  minimized.

While any overload surface is up, the existing `isWorkoutInputSuspended` flag is
set — so the Action Button and Double Tap cannot complete another set during the
flow — and the delayed closure's existing suspension recheck already prevents an
auto-finish from firing behind it. Entering the terminal transition (`isEnding`)
dismisses the surface without staging anything. See
`docs/rep-range-progressive-overload.md`.

Because the trigger sits in `applyToggleSetCompletion`, it is **order-independent** and
covers all three completion entry points, all of which funnel through
`toggleSetCompletion` → `performToggleSetCompletion` → `applyToggleSetCompletion`:

1. On-screen **Complete** button (`CompactActionBar` in `FullScreenSetEditorView`)
2. Apple Watch Ultra **Action Button** (`handleActionButtonPress`)
3. **Double Tap** (also routes through `handleActionButtonPress`)

`findNextIncompleteSet()` already walks standalone exercises sequentially and superset
groups via their interleaved pattern, so the "last round of a superset" and
single-exercise / single-set routines all resolve to nil correctly once every set is
done.

### The finish itself
`autoFinishWorkout()` waits 800 ms, then calls the existing `endWorkout()` (no new
finish machinery). The delay matches the "Done" flash duration in
`FullScreenSetEditorView.toggleSetCompletion` (`showDoneFlash`, 800 ms): without it,
`endWorkout()` sets `workoutSummary` immediately and `ActiveWorkoutView` swaps to the
summary before the celebration flash is visible. Both timers start from the same tap,
so they stay aligned.

Ticket 06 made the delayed task explicitly cancellable by structural editing.
Opening the exercise catalogue/configuration, adding, removing, manually ending,
or discarding cancels the pending task. The delayed closure also rechecks both
`findNextIncompleteSet() == nil` and workout-input suspension before presenting
the dialog or ending. This prevents an all-complete workout from ending behind a
configuration draft, and adding a new incomplete exercise immediately revokes a
previous finish condition.

`endWorkout()` (unchanged) generates the summary before stopping HealthKit, hands the
payload to the durable send queue, then ends the HealthKit session.
`ActiveWorkoutView` shows `WatchWorkoutSummaryView` as soon as `workoutSummary` is set.

## Complete-button relabel ("Finish Workout")
When the set currently displayed in `FullScreenSetEditorView` is the last remaining
incomplete set of the whole workout, the glass Complete capsule (`CompactActionBar`)
reads **"Finish Workout"** instead of "Complete", so the finishing tap reads as
intentional rather than surprising the user with the summary.

- The finishing state is derived in the view model as `WatchWorkoutViewModel.isFinishingSet`:
  the displayed set (`currentSet`) is incomplete **and** the total incomplete-set count
  across all exercises is exactly 1. Same order-independent logic as the auto-finish;
  it's just the pre-tap view of "zero incomplete sets remain after this tap".
- It is passed into `CompactActionBar` as an `isFinishing` flag — the bar holds no new
  state. Label priority in `completionLabel`: Done flash → Undo (set already completed)
  → Finish Workout → Complete. Because `isFinishingSet` requires an incomplete set,
  Finish Workout and Undo are mutually exclusive.
- The VoiceOver label (`completionAccessibilityLabel`) also reports "Finish Workout" in
  the finishing state (checked before the set-position labels).
- New string `"Finish Workout"` localized in `GymStreakWatch Watch App/Localizable.xcstrings`
  (en source + de "Training beenden").

## Template-change prompt
If any set or exercise membership was changed during the workout
(`hasTemplateChanges`), auto-finish does **not**
save directly — it routes through the same **"Update your routine template?"** choice as
the manual End flow (Save & Update Template / Save Don't Update / Continue), then finishes
via the chosen `endWorkout(updateTemplate:)` path. Unmodified workouts still finish
directly.

Mechanism: `autoFinishWorkout()` (after the 800 ms flash delay) checks `hasTemplateChanges`.
If true it sets `WatchWorkoutViewModel.requestsFinishConfirmation`; `ActiveWorkoutView`
observes that flag via `.onChange` and flips its existing `showEndConfirmation` state,
surfacing the **same** `confirmationDialog` the manual "End" buttons use — no duplicated
dialog or template logic. The view resets the flag once presented. Choosing "Continue"
(cancel) leaves the workout active (all sets complete) so the user can still End manually.
Because the trigger lives in the shared completion path, all three entry points
(on-screen button, Action Button, Double Tap) honor the prompt.

The dialog distinguishes set-only, structural-only, and combined changes; a
structural-only workout never claims that a number of sets changed. Before the
dialog or summary appears, catalogue/configuration routes and their draft
selection are cleared so navigation and modal presentation do not collide.

## Scope / deliberate omissions
- The Action Button / Double Tap paths never showed the on-screen "Done" flash (it is a
  `FullScreenSetEditorView` local state); that is unchanged. The 800 ms delay still
  applies so the finish timing is identical across entry points.

## Files touched
- `GymStreakWatch Watch App/ViewModels/WatchWorkoutViewModel.swift` — early auto-finish
  branch in `applyToggleSetCompletion`; new private `autoFinishWorkout()` helper;
  `isFinishingSet` computed property.
- `GymStreakWatch Watch App/Views/CompactActionBar.swift` — `isFinishing` prop; label +
  accessibility relabel.
- `GymStreakWatch Watch App/Views/FullScreenSetEditorView.swift` — passes
  `viewModel.isFinishingSet` into the action bar.
- `GymStreakWatch Watch App/Views/ActiveWorkoutView.swift` — `.onChange` on
  `requestsFinishConfirmation` surfaces the existing template-update dialog.
- `GymStreakWatch Watch App/Localizable.xcstrings` — `"Finish Workout"` (en + de).

## Related
- `docs/watch-set-completion-button.md` — the completion button, haptics, and Done flash.
- `docs/watch-sync.md` — how the completed workout reaches iPhone.
