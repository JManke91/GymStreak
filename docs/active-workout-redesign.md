# Active Workout Redesign (iOS)

## What it is

A full redesign of the **active workout** screen (`ActiveWorkoutView`) — the
screen you are on while training. It is a presentation + interaction redesign:
no `@Model` changes, no schema migration, **no CloudKit schema deploy required**.
Every capability that shipped before it still ships; several moved.

Target: **iOS app only**. The watch target is untouched (`watch-rest-timer-ui.md`,
`watch-set-completion-button.md` still describe the watch).

Source of truth for the visual spec: the Claude Design project *"Workout Aktiv
Redesign.html"* (imported 2026-07-31), backed by `gs-workout.jsx`, `gs-shared.jsx`,
`gs-data.jsx`. The mock's simpler data model did not drive feature removal —
where it had no place for a shipped capability, the capability was kept and the
deviation is recorded under "Deviations from the mock".

## The three problems it fixes

1. **Checking off and editing shared one hit area.** The whole set row was a
   button that expanded an inline editor, with a small completion circle inside
   it. A near-miss opened the editor instead of logging the set.
2. **The list jumped.** Expanding a set pushed everything below it down; the row
   you were aiming at moved out from under your thumb.
3. **Rest took over the screen.** Completing a set auto-opened the full-screen
   rest timer, so you could not log or correct anything while resting.

## Scope decisions (confirmed with the user, 2026-07-31)

- **Only the exercise you are on is expanded.** Everything else collapses to a
  compact tappable row. Chosen over "keep all expanded" and "collapse only
  completed" — the mock's focus idea is the point of the redesign.
- **The rest bar replaces the top banner; the full-screen timer stays,
  opt-in.** Tapping the bar opens it, and the `matchedGeometryEffect` morph was
  retargeted from the deleted top banner to the bar. Live Activity and rest-timer
  notifications are untouched.
- **The set "⋯" menu gets Duplicate + Delete.** The mock also offered "mark as
  warm-up set"; that was **deliberately not implemented** — it needs an
  `isWarmup` flag on `WorkoutSet` (a schema change plus a CloudKit schema
  deploy) and follow-up decisions in history, volume, progress charts and watch
  sync. To add it later: add the attribute, deploy the schema, then decide how
  warm-up sets count everywhere before showing the menu entry.

## How it works

### Screen shell — `ActiveWorkoutView`

`ScrollView` + `LazyVStack` on the pure-black canvas, with:

- `.safeAreaInset(edge: .top)` → `WorkoutProgressHeader`
- `.safeAreaInset(edge: .bottom)` → the rest bar (when resting) + `WorkoutFooterActions`
- a `ZStack` sibling for the large `RestTimerView` overlay

Preserved wholesale from before the redesign: the cancel / finish / workout-complete
alerts, `SaveWorkoutView`, `AddExerciseToWorkoutView`, `DeleteExerciseConfirmationView`,
`SwapExercisePickerView`, `WeightIncreaseSheet`, `SupersetWorkoutGroupView`, the
body-weight card, and the `scenePhase` timer save/restore. The alerts were lifted
into a private `ActiveWorkoutAlerts` `ViewModifier` purely to keep `body` readable.

### Header — `WorkoutProgressHeader`

Routine name, "X of Y sets", an elapsed-time pill, and **one 4pt segment per set,
grouped by exercise**. A bare "4/22" says how much is left but not where you are;
the segments show both, and which exercise the remaining work sits in. Rendered as
one flat `HStack` so every segment is equally wide regardless of how the sets split
across exercises — the extra trailing gap on an exercise's last segment is what
groups them.

### Exercise — `WorkoutExerciseCardView` / `WorkoutExerciseCollapsedRow`

**Opening an exercise scrolls it to the top of the viewport** (`ScrollViewReader`
+ `proxy.scrollTo(activeExerciseId, anchor: .top)` on change). This is not a
nicety: the card that closes is usually *above* the one that opens, so several
hundred points of content leave the list in the same frame. Without the scroll the
viewport keeps its offset and lands somewhere unrelated, which reads as "my tap
did nothing". The same handler covers the automatic hand-off to the next exercise.

Which exercise is open is resolved in `WorkoutScreenData`:

```
openedExerciseId (user tapped a collapsed row, and it still exists)
  ?? viewModel.findNextIncompleteSet()?.exercise.id
  ?? first exercise
```

`openedExerciseId` is set when the user opens a row by hand or **un**-completes a
set (correcting a set is a statement about *that* exercise). On **completing** a
set it is cleared only when the exercise is part of a superset or has no sets
left; otherwise the card stays put.

> **Both halves of that rule are load-bearing.**
>
> *Why supersets must clear it:* `WorkoutViewModel.completeSet` deliberately
> delegates navigation to the view — see its comment *"Navigation is handled by
> findNextIncompleteSet() which ActiveWorkoutView uses"* — and
> `findNextIncompleteSet()` is the only thing that knows a superset's round order
> (A1 → B1 → A2 → B2). Pinning the open card to the exercise just logged would
> strand the user on A while B is the actual next move. Under the old
> all-expanded design the same pin only affected a highlight; with one card open
> it breaks superset flow. **Do not "fix" the card closing on completion by
> re-pinning it for supersets.**
>
> *Why standalone exercises must keep it:* `findNextIncompleteSet()` returns the
> workout's **first** incomplete set. Clearing unconditionally would yank a user
> who deliberately jumped ahead (busy rack, machine taken) back to exercise A
> after every single set. Out-of-order training is a real workflow and it must
> survive.

Card contents: avatar (muscle colour + equipment glyph, `ExerciseAvatarView`),
name, a meta row (`done/total sets · rep goal`), the swap affordance, a "⋯" menu
(remove exercise), the swapped-from indicator, a **Pause chip on its own row**,
the progressive-overload banner, the set rows, and a dashed "Add set".

The **Pause chip** (`ParameterChipButton` + `RestTimeInlineEditor`, both reused from
the routines redesign) replaces the old always-visible `RestTimerConfigView` block.
It is hidden for superset members — a superset rests once per *round*, so
`SupersetWorkoutGroupView` owns that control.

> **The Pause chip gets its own full-width row, and `.fixedSize()`.** It first
> shipped at the end of the meta line, sharing that line with the name, the set
> count, the rep goal and the swap pill. On a real routine the line overflowed and
> SwiftUI truncated the chip's label *and* value away, leaving a bare timer glyph —
> so the rest time, a value you need to read at a glance, was only discoverable by
> tapping the glyph and reading the editor. Do not move it back inline.

### Set row — `WorkoutSetRowView`

A three-column layout: **62pt completion zone | value chips | ⋯ menu**.

- The completion zone spans the full row height and is set apart by its own
  background and a divider. It is the only thing that logs a set.
- The row itself is **not** a button. Right of the divider only the reps and
  weight chips react.
- Reps are coloured orange when outside the rep goal (plus a small orange dot) and
  tint once the goal's upper limit is reached — the cue that precedes a weight
  increase.
- Completed sets keep their completion time and stay editable; the chips just lose
  their frame.

### Value editing — `SetValueKeypadSheet`

Tapping a chip opens a fixed-height sheet: the value large, quick steps
(±1/±2 reps, ±2.5/±5 kg), a numeric keypad, the planned value for reference, an
"apply to all following sets" toggle, and Apply. The list behind it does not move.

It carries its **own keypad** rather than a system keyboard so the sheet height is
fixed and the quick-step buttons stay reachable next to the digits. The decimal
key uses `Locale.current.decimalSeparator`.

> **"Apply to all following sets" propagates exactly one field.** The toggle
> writes only the field the sheet edited to later *incomplete* sets
> (`WorkoutViewModel.updateSet(_:in:reps:weight:propagating:)`). Writing both
> would clobber a ramp-up/pyramid scheme's per-set weights when the user only
> fixed a rep count. Completed sets are never rewritten — they record what
> actually happened. This replaces the old `ApplyToAllBanner` on this screen; the
> banner itself still ships in the routines editor.

### Rest — `WorkoutRestBar`

See `rest-timer-ui.md` for the full morph rules. In short: the bar is the default
rest surface, sits above the footer actions, fills left-to-right as the rest runs
down, offers **+30s** and **Continue**, and expands to `RestTimerView` on tap.
`+30s` goes through `WorkoutViewModel.extendRestTimer(by:)`, which **restarts** the
timer at `remaining + 30` — that is what keeps the notification, the Live Activity
and the persisted deadline consistent with the new end time.

## Rendering: how the main-thread rules are satisfied

`ActiveWorkoutView.WorkoutScreenData` resolves, in **one pass per body
evaluation**, everything the rows render: `WorkoutExerciseDisplay` per exercise and
`WorkoutSetRowItem` (model + `WorkoutSetDisplay`) per set of the open exercise. So:

- No row body walks a SwiftData relationship — not `setsList`, not the routine slot
  behind a swap, not the library `Exercise` behind an equipment glyph.
- No formatter is allocated in a render path (`WorkoutValueFormatting` is static).
- The list is a `LazyVStack`.
- Rows are identified by `WorkoutSet.id` / `WorkoutExercise.id`, never by offset.
- **Cost is scoped to what is visible**: set rows and the swap state
  (`canSwap` / `swapTargets`, which traverse the routine → alternatives → their
  sets graph) are resolved **only for the open exercise**. Collapsed rows need
  neither.
- **The equipment glyph costs no graph walk at all.** It used to come from
  `viewModel.performedExercise(for:)`, which walks `routine.routineExercisesList`
  and (for swapped slots) `slot.alternativesList` — per exercise, per tick. It is
  now an O(1) hit into `equipmentByExerciseId`, a `@State` dictionary built from
  `ExercisesViewModel.exercises` on appear and whenever the library changes.
  `WorkoutExercise.exerciseId` always names what was *actually* performed (a swap
  rewrites it), so no swap handling is needed on this path.
- `allCompletedSetsAtUpperLimit` is computed from the already-materialised `sets`
  array rather than the `@Model` property of the same name, which would walk
  `setsList` a second time.

**Known limit, accepted deliberately.** `WorkoutScreenData` is built inside
`body`, and `body` re-evaluates once per second for the whole workout, because the
view observes `WorkoutViewModel` and that view model owns two 1 Hz timers
(`elapsedTime`, `restTimeRemaining`). This is *not* a regression — before the
redesign every mounted card ran the same walks in its own body — and it is bounded
by a single workout (tens of sets), unlike the unbounded history lists that caused
the 630 ms hang in `history-performance.md`. If it ever measures as a hang, the fix
is to hold `WorkoutScreenData` in `@State` and rebuild it on an explicit revision
counter rather than on every body pass; narrowing the observation would require
migrating `WorkoutViewModel` to `@Observable`.

## Deviations from the mock (deliberate)

| Mock | Shipped | Why |
|------|---------|-----|
| Bare `arrow.triangle.2.circlepath` icon button for swap | **Labeled pill** ("Swap" + icon) | `alternative-exercises.md` records that a bare glyph was tested and read as refresh/sync. The documented finding beats the mock. |
| No superset concept | `SupersetWorkoutGroupView` kept, wrapping collapsed rows / the open card | Supersets ship; the mock's data model simply has none. |
| No delete-exercise, add-exercise, body weight, progressive overload | All kept — delete in the card's "⋯" menu, add-exercise as a dashed button below the list, body weight as a card at the top (only when the workout has a counterweight-assistance exercise), overload banner inside the open card | The mock is a smaller app. |
| Rest time shown as static text | Tappable Pause chip → `RestTimeInlineEditor` | Per-exercise rest config is a shipped feature. |
| Planned values not shown | Shown in the keypad sheet | The old expanded editor showed them; they are the reference the logged value is judged against. |
| "Mark as warm-up set" in the set menu | Not implemented | Schema change — see "Scope decisions". |
| German copy inline | All strings localized (en + de) | App is localized. |

## Components

| Component | File | Role |
|-----------|------|------|
| `ActiveWorkoutView` | `Presentation/Views/Workout/ActiveWorkoutView.swift` | Screen shell, `WorkoutScreenData`, all sheets/alerts, superset group, body-weight card |
| `WorkoutExerciseDisplay` / `WorkoutSetDisplay` / `WorkoutSetRowItem` / `WorkoutValueFormatting` | `.../ActiveWorkoutDisplay.swift` | Value structs + static formatting the rows render from |
| `WorkoutProgressHeader` | `.../WorkoutProgressHeader.swift` | Routine, elapsed time, per-set segment bar |
| `WorkoutExerciseCardView` | `.../WorkoutExerciseCardView.swift` | The open exercise |
| `WorkoutExerciseCollapsedRow` | `.../WorkoutExerciseCollapsedRow.swift` | Every other exercise |
| `WorkoutSetRowView` | `.../WorkoutSetRowView.swift` | Completion zone / value chips / set menu |
| `SetValueKeypadSheet` | `.../SetValueKeypadSheet.swift` | Value editor |
| `WorkoutRestBar`, `WorkoutFooterActions` | `.../WorkoutRestBar.swift` | Rest bar and the cancel/finish footer |

**Deleted:** `CompactRestTimer.swift`, and the `TimerHeader`, `ExerciseCard`,
`WorkoutSetRow` and `ActionBar` types that lived inside the old
`ActiveWorkoutView.swift`.

**View-model additions** (`WorkoutViewModel`): `duplicateSet(_:in:)`,
`extendRestTimer(by:)`, and `updateSet(_:in:reps:weight:propagating:)` — which
replaced `updateSet(_:reps:weight:)` (that overload had no callers outside this
screen).

## Traps / non-obvious details

- **`var id: UUID { self.set.id }` needs the explicit `self`.** A bare `set` at
  the start of a computed-property body parses as the `set` accessor keyword and
  fails with *"expected '{' to start setter definition"*.
- **`WorkoutScreenData` must be `@MainActor`.** Its initializer reads the
  `@MainActor` view model; without the annotation Swift 6 rejects the calls as
  main-actor-isolated in a nonisolated context.
- **`WorkoutExerciseCardView` uses an explicit initializer** rather than relying
  on the memberwise one for its two `@ViewBuilder` parameters.
- **Never put the same `.id()` on both branches of the expanded/collapsed
  conditional.** `exerciseView` applies `.id(exercise.id)` to the enclosing
  `Group`, not inside the two branches. Tagging both branches with the same
  explicit id tells SwiftUI they are one view, which overrides the structural
  identity that `_ConditionalContent` relies on to swap branches; inside a
  `LazyVStack` that made an already-realized collapsed row survive the state
  change. The symptom is nasty because everything else works: the tap registers,
  the haptic fires, `openedExerciseId` updates — and the row just stays
  collapsed. The id on the container keeps the `scrollTo` anchor and restores
  ordinary branch diffing.
- **Rest bar and large timer must stay in the same view tree.**
  `matchedGeometryEffect` cannot cross a `.sheet` boundary — this is why the large
  timer is an in-tree overlay and not a sheet. See `rest-timer-ui.md`.
