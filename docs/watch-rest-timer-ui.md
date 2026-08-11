# Rest Timer UI (watchOS)

## Overview

During an active watch workout the rest countdown has two states:

- **Large** (`RestTimerLargeView`) — a full-screen countdown: gradient progress
  background that drains bottom-up, HR/kCal + elapsed time on the top row, the
  big monospaced countdown in the center, **Minimize** / **Skip** at the bottom.
  Pulses red in the last 3 seconds and plays notification haptics at 3/2/1 and a
  success haptic at 0.
- **Minimized** (`RestTimerMinimizedPill`) — a small pill (≤96×22 pt) with a
  draining capsule bar behind the remaining seconds and a chevron. **Tap** to
  expand, **long-press (0.5 s)** to grow it into the inline `−15 · 1:45 · +15`
  stepper (`RestPillStepper`).

Both are mounted by a single component, `WorkoutRestTimerOverlay`, which
`ActiveWorkoutView` places in its root `ZStack` as a **sibling of the
NavigationStack**. State comes from `WatchWorkoutViewModel`
(`isResting`, `isRestTimerMinimized`, `restTimeRemaining`, `restDuration`,
`restTimerState`).

> Scope: **watchOS target only.** The iOS rest timer is a separate
> implementation with its own morph and constraints — see `rest-timer-ui.md`.
> For the notification side see `rest-timer-notifications.md`.

Design reference for the Crown adjustment:
[Watch Pause Anpassen](https://claude.ai/design/p/0d4ac3f4-2c40-43cc-b80e-84bd411c334a?file=Watch+Pause+Anpassen.html)
(frames A1/A2 = idle vs. editing, A3 = the scope prompt, C1 = 41 mm space
probe). Frame B3 — long-press on the training-time chip when no rest runs — is
deliberately **not** built.

## Behavior

- A rest starts when a set is completed and that set's `restTime > 0` and it is
  not the last set (`WatchWorkoutViewModel.startRestTimer`). The large timer
  opens automatically (`isRestTimerMinimized` is reset to `false`).
- **Minimize** collapses to the pill; **tapping** the pill expands again;
  **long-pressing** the pill opens its inline stepper (see "Adjusting from the
  minimized pill"). Both pill gestures play a haptic. Minimize and expand are a
  continuous **morph**, not a cross-fade — see "The large↔minimized morph".
- The pill sits at the **top-trailing corner of the safe area** and stays there
  on every screen of the workout: exercise list, metrics page, controls page and
  the pushed full-screen set editor. It also stays put while the carousel list
  scrolls.
- While the pill is shown, the set editor's own top-trailing accessory (the
  elapsed-time label) is hidden, so the two never stack.
- The countdown keeps running across tab switches and navigation pushes/pops —
  there is only ever one timer view reading one view-model.

## Adjusting the rest duration with the Digital Crown

Turning the Crown during a running rest changes the **rest duration**, not just
the countdown. The countdown moves by the same delta, and the new duration is
written to every set of the owning exercise(s) so the *next* rest of that
exercise starts at it.

- **Step and bounds:** 5 s per detent, clamped to **0:05–10:00**
  (`WatchWorkoutViewModel.restDurationRange` / `.restDurationStep`).
  `isContinuous: false` clamps at the ends; `true` would wrap 10:00 back to 0:05.
- **The digits take the badge's tint** while the Crown is changing them, so the
  number reads as the thing being edited. Colour and glow only — they carry
  `matchedGeometryEffect` and `.fixedSize()`, so their size and position are
  off limits. The last-3-seconds red always wins over it: urgency outranks
  editing.
- **The digits never move.** Only the chrome changes: the "REST" caption
  cross-fades (120 ms) into a `+15 s` delta badge, and a tick track plus a
  `1:30 → 1:45` line appear. Neither piece takes layout space of its own — the
  badge is an **overlay on the caption**, and the footer **borrows the
  Minimize/Skip slot**, cross-fading with the buttons for as long as the
  adjustment is on screen (`.restAdjustmentFooter(_:isAdjusting:)`). The
  buttons stop hit-testing while invisible, so a tap during a rotation cannot
  skip the rest by accident, and they are back 1.2 s after the Crown settles.

### The vertical budget, and two layouts that failed

This screen has **no spare vertical space**, and that is the single fact that
shaped the editing state. On a 46 mm watch (208×248 pt) the metrics row, the
caption, the 44 pt digits, the button row and 12 pt of vertical padding leave
roughly **29 pt in each `Spacer`** — enough for the tick track, not for the
tick track *and* a text line. 41/42 mm is tighter still.

**Below 41 mm every fixed value on this screen has to come down** (added
2026-08-11). A 40 mm watch is 162 × 197 pt — 18 pt shorter than the 41 mm frame
the design was drawn on — and with the 46 mm constants the column ran ~40 pt
past the display: the Minimize/Skip row was laid out off the bottom edge. Five
of this view's constants are now `WorkoutScreenMetrics` tiers (49/45 · 41 · 40 mm):
`restCountdownSize` (44/42/34), `restVerticalPadding` (12/10/4),
`restStackSpacing` (6/6/3), `restCenterSpacing` (6/6/2) and
`restMinimizeIconSize` (24/22/18). The compact HR/kCal readout in the top row
(`WorkoutMetricsView(size: .small)`) is tiered too — it was the tallest single
element here at ~39 pt and is ~31 pt on 40 mm. See
`watch-set-completion-button.md` § "Sizing per Case" for the full table and the
two-axis tier rule.

The design (frames A1/A2) stacks badge → digits → ruler → `old → new` around
the countdown; that arrangement assumes room this screen does not have, which
is presumably why the designer added the C1 "41 mm space probe" frame. All
three elements survive here, but the last one had to move into a borrowed slot
rather than get one of its own.

Both earlier attempts were tried on device and failed:

1. ⚠️ **Fixed-height reserved slots.** Caption and footer as always-present
   frames. Stable in isolation, but ~36 pt added to a column between two
   `Spacer`s pushed the content past the safe area **at both ends** — the
   metrics row rose into the system clock and the Minimize/Skip buttons were
   cut off at the bottom edge.
2. ⚠️ **Footer hung below the digits via an alignment guide**
   (`.alignmentGuide(.bottom) { $0[.top] - spacing }` inside
   `.overlay(alignment: .bottom)`). Genuinely layout-neutral, and the technique
   itself is sound and Apple-documented — but with only 29 pt of gap it drew
   the ruler and the `old → new` line straight over the buttons.
3. ⚠️ **`safeAreaInset(edge: .bottom)`** was never built: its documented
   contract is to inset the modified view to make room, i.e. attempt 1 under a
   different name.

The surviving rule: **anything added to this column must be layout-neutral
*and* fit in space something else is not using.**

Notes on the overlay technique, confirmed against Apple's docs (2026-08-10)
since attempt 2's machinery is still what places the badge:

- An overlay's **base view keeps providing the layout characteristics of the
  combined view**, which is what guarantees the slot never changes size.
- Overriding a child's alignment guide to place it outside its host is the
  documented use of `alignmentGuide(_:computeValue:)` — Apple's own "Aligning
  views within a stack" sample does the same move. Reading the child's own
  `ViewDimensions` (rather than an `.offset(y:)` with a hardcoded height) is
  what makes it survive Dynamic Type and translation.
- Plain stacks do not clip, so drawing outside the bounds is safe **here**; a
  `List`, `ScrollView` or paged `TabView` would clip it.
- SwiftUI hit-tests at rendered position, not at the declared layout box, so
  decorative content drawn outside its host needs `.allowsHitTesting(false)`.
- **After the rotation settles** (`onIdle`) the change is checkpointed and the
  chrome fades back to the idle presentation 1.6 s later.
- Skip, Minimize, the large↔pill morph and the re-toggle guard are untouched.

### The scope prompt ("This rest" / "All sets")

Writing to every set is the *right default* — the usual reason to turn the Crown
is that the configured duration is generally wrong — but it is not always what
the user meant. A moment after the Crown settles, a flat two-option row springs
in below the countdown with **All sets** already selected:

- It is a **confirmation, never a blocker.** Ignoring it leaves the all-sets
  write in place. Skip, Minimize and the pill morph stay reachable straight
  through it.
- **"This rest"** demotes the change to the running countdown: `restDuration` /
  `restTimeRemaining` keep the dialed-in value, and the owning exercises' sets go
  back to what they were. It is a **revert of a write that already happened**,
  not a deferred commit — ticket 01 writes on `onIdle`, which is *before* the
  prompt appears.
- **"All sets"** re-asserts the current duration rather than doing literally
  nothing: after a "This rest" the sets hold the old value again, so changing
  one's mind inside the prompt's lifetime has to write it back. In the normal
  case the write is a no-op by value.
- The row lives **3 s** (`RestScopeRow.life`) and slides away, leaving the choice
  in effect. Selecting does not extend or shorten that.

**What "the previous duration" means.** `preAdjustmentRestTimes` is a snapshot of
the owning exercises' set rest times, keyed by set id, captured by the *first*
commit of the rest (before the first write) and held until the rest ends. A
snapshot rather than one `TimeInterval` because nothing guarantees a group's sets
started on the same value — only the write path flattens them. It survives a
second rotation on purpose, so a later "This rest" reverts all the way to the
original rather than to the previous adjustment. The owners are
`restAdjustmentExerciseIDs`, so a superset round reverts the **whole group**,
exactly as it was written.

Nothing about the running countdown is checkpointed (the recovery payload
carries `exercises` only), so "This rest" is also the correct state after a
mid-workout relaunch: the reverted sets are what persists.

Known edge, accepted: swapping an exercise *while its rest runs* replaces the
sets, so the snapshot's set ids no longer match and `restoreRestTimes` silently
skips them — the swapped-in exercise keeps the adjusted rest. Reverting to a set
that no longer exists has no better answer, and the window is a few seconds wide.

### Timing, and why the prompt and the editing chrome never coexist

One task (`chromeLingerTask`) drives the whole tail of an adjustment, so the two
stages cannot race:

```
onIdle → commit → 1.2 s → editing chrome out + row in (All sets) → 3 s → row out
```

The 1.2 s is `chromeLinger`, reused as the prompt's arming delay — the design's
"~1 s after the last detent". The two states are deliberately **mutually
exclusive**: the badge/ruler/`old → new` block leaves in the same transaction the
row arrives in.

That is a layout requirement, not a stylistic one. The row costs about 27 pt and
this column has ~29 pt of slack at 46 mm and roughly half that at 41 mm (see "The
vertical budget"), so it is paid for by **collapsing the "REST" caption while the
row is up** — the one line that says nothing while a choice is on screen. Net
change against the idle layout is ≈ +10 pt. Having the ruler, the row and the
caption up at once would not fit at 41 mm.

**Neither half of that exchange may use a removal transition**, and both sides of
the code say so:

- The caption is **collapsed** (`.frame(height: 0)` + `.opacity(0)`), not removed
  by an `if`. A view removed by a transition keeps its layout slot until the
  transition finishes, so an `if` would hold caption *and* row in the column for
  the length of the spring — attempt 1's overflow, on a timer.
- The row's transition is **asymmetric**: it springs in (`.scale` + `.opacity`,
  `response: .3, damping: .8`) but leaves with `.identity`, i.e. instantly. Its
  slot is free by the time it appears, but an animated exit would hold ~27 pt
  while the caption reclaims its own. The design's "slides away" loses to the
  budget; the arrival, which is the part the user is reading, keeps its spring.
- The caption's opacity runs on the 0.12 s `crossfade`, **not** the row's spring.
  A zero-height frame does not clip, and it must not — the delta badge overflows
  the caption on purpose — so a 0.3 s fade would ghost the caption over the
  digits on its way out.

"Never on screen together" is exact for **layout** and approximate for pixels:
the footer's 0.12 s fade-out runs while the row springs in, so a ruler at low
opacity can be drawn behind the arriving row for that long. It occupies no space
and does not hit-test, so it costs nothing but a soft handover.

A rotation while the row is visible therefore **re-arms the one row** instead of
stacking a second: the new adjustment cancels the task, the row leaves, and the
chain restarts from `onIdle` with "All sets" preselected again — which is
accurate, because the fresh commit did write to all sets.

Both stages are torn down together when the **rest** ends
(`canAdjustRestDuration` going false). Cancelling the task alone would strand
whichever stage it had not reached — a half-faded chrome, or a row that never
dismisses.

Deliberately **not** on the morph half of `isEnabled`: tearing the chrome down as
a minimize starts would change this column's layout in the same frame the shared
digits begin interpolating. Minimizing unmounts the large state anyway, so the
row cross-fades out with the rest of its chrome.

### What gets written, and why supersets are different

`WatchWorkoutViewModel.updateRestTime(for:newRestTime:)` is the write path for
**setting** a rest duration: it takes a list of exercise ids and writes the
duration to every set of each, completed ones included. Its only counterpart is
`restoreRestTimes(_:)`, which puts the pre-adjustment snapshot back for "This
rest"; it writes `set.restTime` directly rather than through `updateRestTime`
because it restores a *per-set* value instead of one duration, and its
`canMutateWorkout` guard therefore sits on its caller,
`applyRestAdjustmentScope(_:)`. Nothing else may write `restTime` during a
workout. Both take their exercise list from `restAdjustmentExerciseIDs`,
captured when the rest starts:

| Rest started by | Owners |
|-----------------|--------|
| a normal exercise | that exercise |
| a superset round | **every member of the group** |

The superset case is not defensive coding. `supersetRoundRestTime` resolves a
round's rest from the **last** exercise of the group at that set level, so
writing only to the exercise whose set was completed would leave the next round
running on the stale value.

**The write is buffered, not per detent.** `adjustRestDuration(to:)` moves only
`restDuration` / `restTimeRemaining` and parks the new value in
`pendingRestDuration`; `commitRestDurationAdjustment()` is what writes it into
`exercises` and checkpoints it. That is a hard requirement, not a nicety:
`exercises` is `@Published` and the whole active-workout tree observes this view
model, so writing it 5–10×/s would republish the entire workout state and
re-render the exercise list (whose progress header reduces over every set) and
the pushed set editor for the length of the rotation — during a live
`HKWorkoutSession`.

The commit runs at **three** points, so a buffered value can never be dropped:
`onIdle` (rotation settled), and `stopRestTimer()` / the natural-completion
dismissal — skipping or elapsing a rest right after a rotation unmounts the
timer, and its `onIdle` would then never arrive.

### Reaching the routine template ("Save & Update Template")

Everything above changes the **running workout**. Whether the new duration also
changes the *routine* is decided by the existing finish dialog — the same toggle
that already governs set values and structural edits. There is deliberately no
second prompt: iOS behaves this way for an iPhone workout, so the two platforms
end up identical. Declining leaves the change session/history-only and the
routine byte-for-byte untouched.

**The baseline is what makes it detectable.** `restTime` is mutated in place by
an adjustment, so a rest-only change would otherwise be invisible. Each
`ActiveWorkoutSet` therefore carries `plannedRestTime` — what the set started the
workout with, taken from the routine (or from the alternative's scheme on a
swap, or the draft on a watch-added exercise) — and `wasRestModified` is simply
`restTime != plannedRestTime`. It is optional: a checkpoint or payload written
before the field existed decodes as *no rest intent*, never as a change.

`wasRestModified` is **not** part of `wasModified`. A rest change is one change
per exercise, not per set, so folding it in would inflate the dialog's "you
modified N sets". It surfaces as `hasRestChanges` → `hasTemplateChanges`, and
as its own `WatchWorkoutFinishDialogState.restOnly` message ("You changed the
rest time. Update your routine template?"), which is reached only when nothing
else changed — any set or structural change already offers the update and the
rest rides along with it.

Two consequences of the "one rest per exercise" model, both intentional:

- The exercise's **first** set's rest is what reaches the template, and it is
  written to *every* template set of that exercise, performed or not. The write
  path here always sets all sets uniformly, so the two agree.
- "This rest" (the scope prompt) reverts the sets, which also clears the intent
  — with nothing differing from the baseline there is nothing to carry.

Rest is **not** subject to the progressive-overload exclusion. An exercise whose
overload was applied keeps its committed reps/weight, but its rest is still
written — the overload transaction commits values only, so no rest value of its
own can be regressed. Same rule on iOS, where `updatePrimaryTemplateSets`
assigns `restTime` outside its value-writeback guard.

The protocol side — the `restTime`/`plannedRestTime` wire pair, the optimistic
fold, and the all-or-nothing iOS merge — is documented in `docs/watch-sync.md`,
"Rest duration intent".

#### The buffered write vs. the finalization freeze (root cause, 2026-08-11)

A device pass found the whole path silently dropping the change, and the cause
was **the buffer, not the sync**. `endWorkout` sets `isEnding = true` — which
makes `isWorkoutFrozen`, and therefore `!canMutateWorkout`, true — *before* it
calls `stopRestTimer()`. That call is one of the three commit points, so the
sequence was:

```
isEnding = true            → canMutateWorkout == false
stopRestTimer()
  → commitRestDurationAdjustment()
      pendingRestDuration = nil        ← buffer cleared…
      updateRestTime(…)                ← …by a write that then no-ops
```

An adjustment that had not yet been flushed by `onIdle` (or by the pill's
collapse) was therefore **cleared without ever being written** — it never
reached `exercises`, so it never reached the payload, the template, or even the
workout's own remaining sets. Two fixes, both load-bearing:

1. `endWorkout` commits **before** it freezes (and after it clears input
   suspension, so the flush depends on that function rather than on every
   caller), so the flush still passes the mutation guard.
2. `commitRestDurationAdjustment()` checks `canMutateWorkout` *before* clearing
   `pendingRestDuration`, so a blocked write defers the value to the next commit
   point instead of discarding it. This is what makes every surface safe — the
   large timer, the pill, and any interruption in between.
3. …but the deferral has a boundary, and it is load-bearing: **the buffer holds
   a duration, not its owners.** `commitRestDurationAdjustment` resolves the
   target exercises from `restAdjustmentExerciseIDs` *at commit time*, and both
   rest teardowns (`stopRestTimer()` and the natural-completion dismissal) clear
   those owners. A value they could not write must therefore die with the rest
   that owned it — otherwise a later rest's commit would write it to a
   **different exercise** with no user rotation behind it. Both teardowns clear
   `pendingRestDuration` after their flush attempt for exactly that reason.

**No automated coverage**: `WatchWorkoutViewModel` is not in the `GymStreakTests`
target, so this class of bug stays device-only. The two diagnostics below exist
because of it.

#### Diagnosing a "my rest did not sync" report

Two log lines answer it without a debugger, one per device:

**The failure this section was written for turned out to be downstream of both.**
The watch sent the intent, the iPhone received it, the merge resolved and
committed it — and the routine still did not change, because the isolated
transaction's write lost a row-version conflict and the main-context mirror that
would have re-established it did not copy `restTime`. That is documented in
`docs/watch-sync.md` ("The main-context mirror is load-bearing, not a cache");
the table below stays because it is what localized the failure to that hop.

| Device | Line | Reading it |
|--------|------|------------|
| Watch, at finalization | `finalize: template intent — N modified set(s), rest changed on M exercise(s)` | `M == 0` ⇒ the watch never recorded the change (buffer dropped, or the watch app predates `plannedRestTime`). The iPhone cannot fix that. |
| iPhone, on ingest | `ingest: split template applied — rest intent on M exercise(s)` | `M == 0` with a non-zero watch count ⇒ the payload lost it in transit, or **the iPhone build predates the field**. An outcome of `rejected` means the whole transaction was refused, rest included. |
| iPhone, on merge (Xcode only) | `Template transaction applied: … rest intent on M exercise(s) → K set(s)` | `M > 0, K == 0` ⇒ the template already held that value, so there was nothing to write. |

Both go through `WatchSyncDiagnostics` (the unified log, readable from a device
in Console.app). The merge lines reach it via a closure the coordinator injects
into the service, since Domain may not import the Data-layer logger; a third line,
`merge: committed N update(s), K with rest; rest now […]`, states what the routine
holds immediately after the commit, which is what distinguishes "never written"
from "written and then lost".

Both apps must be built from the same revision: `plannedRestTime` is additive and
optional, so a mixed pair decodes fine and simply behaves as "no rest intent" —
it fails silently, exactly like the bug above.

### Adjusting from the minimized pill

A rest can also be fixed **without pulling the large timer back up**:
long-pressing the pill grows it into an inline stepper — `−15 · 1:45 · +15` —
and hands it the Digital Crown for as long as it is open. The taps make the
capability discoverable; the Crown keeps working in parallel at its usual 5 s
detent for anyone who expects it. Three seconds after the last input the pill
shrinks back to the plain countdown and the change is committed.

- **Both inputs, one write path.** ± taps and Crown detents both go through
  `adjustRestDuration(to:)`, and the collapse calls
  `commitRestDurationAdjustment()` — ticket 01's buffered write, including the
  superset fan-out and the checkpoint. There is no second write path, and the
  pill never writes per detent.
- **± is 15 s, the Crown is 5 s.** A tap is a decision ("this rest is too
  short"), a detent is a nudge — and the pill has room for two targets, not
  twelve. Same 0:05–10:00 clamp and the same once-per-arrival limit haptic
  (`RestLimitHaptic`, shared with the large timer's path).
- **The 3 s collapse restarts on every input.** `onIdle` covers Crown idleness
  only, so the cancellable `Task.sleep` is restarted from the tap handlers *and*
  from every detent — a rotation longer than 3 s would otherwise collapse the
  stepper mid-turn.
- **No scope prompt here.** The pill writes to all sets, full stop. The
  "This rest / All sets" row (ticket 02) needs ~27 pt of column that the pill
  does not have, and it is armed from the large timer's `onIdle`. Reaching for
  the one-time escape hatch means expanding the timer.
- **Long-press-to-skip is gone** (deliberately — see below). Skipping runs
  through tap-to-expand → **Skip**.

#### Why it is an overlay, not a wider pill

The stepper is drawn as an **`.overlay(alignment: .trailing)` on the pill's
card**, extending leftward, and the pill's own chrome is faded to `opacity(0)`
underneath it. Nothing about the pill's layout changes when it opens.

That is what makes "grows in place" exact rather than approximate. The pill's
drawn position is the product of three tuned constants —
`WorkoutRestTimerOverlay.trailingInset`, `.baselineLift` and the pill's
`touchInset` — inside a `.frame(maxWidth:maxHeight:)` box that **centers** the
pill in it. Widening that box would therefore move the drawn pill horizontally,
and any compensation would have to hardcode the collapsed pill's intrinsic
width. An overlay takes no layout space, so it sidesteps all of it: same box,
same height, same vertical position, guaranteed by construction rather than by
arithmetic.

Consequences worth knowing:

- The stepper is proposed the pill **card's** size, so it inherits the card's
  height and only overrides its width — hence the overlay sits *before* the
  `.padding(touchInset)`, not after it.
- It draws far outside its host's bounds. That is safe here (plain stacks do not
  clip, and neither does `geometryGroup()`), and SwiftUI hit-tests at rendered
  position, so the ± halves outside the pill's box still receive taps —
  **confirmed on device 2026-08-11**, including the `−15` half, which lies
  wholly outside the box and under an ancestor `.contentShape(Rectangle())`.
- The pill's surface and digits keep their `matchedGeometryEffect` ids while
  hidden — opacity does not affect layout — so a tap-to-expand *while the
  stepper is open* still morphs from the right frame. The flip back to
  `opacity(1)` must run **inside a transaction**
  (`WorkoutRestTimerOverlay.closeStepper()`): it happens in the same frame the
  pill starts being removed, and unanimated it flashes the pill's own digits
  over the shared ones mid-morph.
- **The pill's tap gesture yields while the stepper is open.** Its hit region
  sits under the stepper's right half and part of the duration readout — which
  is not a Button — so a tap there buys another 3 s instead of expanding. Tapping
  to expand works again the moment the stepper collapses.
- The stepper is built only inside `if isStepperOpen`. This body re-evaluates
  once a second from the countdown alone.

**Width is tiered** (`WorkoutScreenMetrics.restPillStepperWidth`, 136/132/126/116)
because the stepper grows *into* the screen: at 40 mm the pill's card has ~120 pt
of room to its left before the display edge.

**Hit targets: 40 × 40 pt per half, not 44.** The ticket asked for ≥ 44 pt, which
is the **iOS** figure; this project's watch design handoff §6 puts the watchOS
floor at 24 pt, which is what `ChevronCircleStyle` enforces on the set editor's
own controls. 40 pt clears that comfortably while leaving the grown pill inside a
40 mm display; two 44 pt halves plus the duration would not fit there. The region
is a `contentShape`, so it does not depend on glyph size, and it overflows the
drawn card vertically instead of making it taller.

#### The gesture reassignment (long press no longer skips)

Long-pressing the pill used to **skip the rest**. The design reassigns it to the
stepper, and both cannot coexist: the pill has exactly two gestures' worth of
room, and tap-to-expand is not negotiable. Skipping is still one tap away
(expand → Skip), whereas *fixing* a rest previously had no path from the pill at
all — that trade is the point of the feature.

Two notes for future work:

- **Long press as a "more options" gesture is not a HIG-backed watchOS idiom** —
  on watchOS the system associates it with Home Screen / complication editing.
  It is a deliberate design choice, not an Apple pattern.
- **Stacked `.onTapGesture` + `.onLongPressGesture` is a documented-fragile
  combination** (reports of the tap never firing, e.g.
  [forum 760062](https://developer.apple.com/forums/thread/760062)). Both
  modifiers are the ones the pill already carried — only the long press's action
  changed — so this is low risk, but if tap-to-expand ever stops firing the
  fallback is explicit `.gesture(LongPressGesture()…)` +
  `.simultaneousGesture(TapGesture()…)` composition.

### Crown ownership

Crown routing is effectively **single-owner** and watchOS has **no
focus-restoration stack**, so ownership is modelled explicitly rather than left
to two views each declaring `.focusable(true)`:

```swift
enum WatchRestCrownOwner { case none, largeTimer, pillStepper }
```

`WorkoutRestTimerOverlay` **derives** it — it is a computed property, never
stored, so no code path can leave two owners set — and each candidate declares
`.focusable(crownOwner == .<itself>)`:

| Situation | Owner | Effect |
|-----------|-------|--------|
| Large timer up | `.largeTimer` | it covers the whole display, so it takes the Crown |
| Pill, stepper closed | `.none` | the exercise list underneath keeps Crown scrolling |
| Pill, stepper open | `.pillStepper` | the pill takes it for the stepper's 3 s |
| Morph in flight, or no rest | `.none` | Crown input is inert |

One gap, accepted: opening the stepper within one `WatchRestTimerMorph.response`
(0.42 s) of a minimize leaves it open with the owner still `.none`, so the Crown
scrolls the list underneath for that window. It self-heals when `isMorphSettled`
flips, and the ± taps work throughout — no path can strand the stepper with
nobody able to reach it.

Hand-back is the same flip in reverse: collapsing the stepper returns the owner
to `.none`, and the views under the overlay (the carousel list's scroll, a
pushed destination) get the Crown back immediately. Both candidates also mirror
the value into a `@FocusState` and toggle it on change — there are forum reports
of crown focus not moving reliably across pushed views without an explicit state
toggle ([683806](https://developer.apple.com/forums/thread/683806)).

Focus is **not** scoped by navigation depth, which is why an overlay that is a
sibling of the `NavigationStack` can take the Crown from a `List` or from a
pushed destination in the first place. That configuration is not covered by
Apple's documentation — it follows from the single-owner model — so it needs
device verification.

Ownership is additionally gated on `isMorphSettled` — Crown input is inert while
a large↔pill morph is in flight. That flag lives on `WorkoutRestTimerOverlay`
and is driven off `viewModel.isRestTimerMinimized` changing (not off
`setMinimized`), so state-driven switches — a rest elapsing while minimized —
count as a morph too. Like the re-toggle guard it is released by the **wall
clock**, never by an animation-completion callback (see rule 8 below for what
happened the one time that was tried).

### The screens make room, again

The grown pill reaches across the top of whatever screen is below it, so the set
editor's **"Exercise 1 / 7" label fades out** while the stepper is up and returns
when it collapses. It is faded, not removed: the row's height must not change
under the pill, and the segment bar below it stays.

The flag travels as an **environment value** (`\.isRestPillStepperOpen`), owned
by `ActiveWorkoutView` — the overlay is a *sibling* of the screens that read it,
so the state has to live in their common parent. `WorkoutRestTimerOverlay` takes
it as a `@Binding`; only views that actually read the key re-render when it
changes, which is why it is not another `@Published` on the view model.

### Implementation rules

1. **`.focusable()` must precede `.digitalCrownRotation(...)`** in the modifier
   chain, or Crown input silently does nothing.
2. **The per-detent click is automatic** (`isHapticFeedbackEnabled: true`). Do
   **not** also play `WKInterfaceDevice.current().play(.click)` — it doubles up.
3. **There is no built-in limit haptic.** The bound is detected in the change
   handler and `.directionDown` / `.directionUp` is played manually, once per
   arrival at the bound rather than once per detent.
4. **`sensitivity:` is passed explicitly.** Apple's overview page documents the
   default as `.medium` and the `detent:` overload's own page as `.high` — the
   docs contradict each other, so nothing is inherited. Sensitivity changes
   rotation-per-detent, not step size; `by:` is what makes the 5 s feel.
5. **`.contentTransition(.numericText())` only in the settled state, and
   throttled.** A `Text` has one active content transition, and a
   glyph-replacing one would override the `.contentTransition(.identity)` the
   shared digits carry to survive `matchedGeometryEffect` — so the digits stay
   on `.identity` while a morph runs. Raw detents arrive 5–10×/s at this
   sensitivity, so the *value* is committed on every detent (the model never
   lags the Crown) but only every 150 ms inside an animated transaction.
6. **`onIdle` is the "rotation ended" signal** — no hand-rolled debounce. It
   covers Crown input only, not taps.
7. **Neither the set write nor the checkpoint runs per detent** (see above).
   `updateRestTime` is deliberately silent and non-persisting;
   `commitRestDurationAdjustment()` is what makes the change survive a
   mid-workout relaunch (see `watch-workout-recovery.md` — the checkpoint
   carries `exercises`, so the adjusted `restTime` rides along).
8. **The editing chrome is built only while adjusting.** The 25-capsule tick
   track, its gradient mask and the `old → new` formatting sit behind
   `if isAdjusting` — this body re-evaluates once a second from the countdown
   alone, so none of it may be constructed just to be hidden.

### API research (2026-08-10)

- The real modifier is
  [`digitalCrownRotation(detent:from:through:by:sensitivity:isContinuous:isHapticFeedbackEnabled:onChange:onIdle:)`](https://developer.apple.com/documentation/swiftui/view/digitalcrownrotation(detent:from:through:by:sensitivity:iscontinuous:ishapticfeedbackenabled:onchange:onidle:)-17066)
  (watchOS 9.0+). Its generic parameter is `BinaryFloatingPoint`, so the binding
  is a `Double`/`TimeInterval` — **there is no `Int` overload**. The
  `digitalCrownRotation(detent: .by(5))` shorthand in the design mock is not
  real API.
- Haptics during an active `HKWorkoutSession` carry no documented restriction,
  and the target's existing Crown users already play them mid-workout.
- Sources: [`contentTransition.numericText`](https://developer.apple.com/documentation/swiftui/contenttransition/numerictext(countsdown:)),
  [`WKInterfaceDevice.play`](https://developer.apple.com/documentation/watchkit/wkinterfacedevice/1628128-playhaptic?language=objc),
  [crown haptic defaults (forum 115562)](https://developer.apple.com/forums/thread/115562).

### Deliberately not built (this slice)

- **No adjustment when no rest is running.** (Adjusting *from the pill* was out
  of scope for ticket 01 and built by ticket 03 — see "Adjusting from the
  minimized pill".)
- **The scope prompt is Crown-only.** It is armed from `onIdle`, which covers
  Crown input and nothing else — the VoiceOver `accessibilityAdjustableAction`
  commits to all sets with no prompt, for the same reason it gets no editing
  chrome (the spoken value is the feedback).
- **VoiceOver gets no editing chrome.** The countdown element carries an
  `accessibilityAdjustableAction` that steps the duration and commits
  immediately — the spoken value is the feedback, so the badge/ticks/`old → new`
  block (and its linger timer) is skipped on that path.

### Verification state

The Digital Crown cannot be driven by XCUITest, so this is a manual-pass
feature. **Fully verified on device 2026-08-10** at 46 mm and 41/42 mm and at
the largest watch text size: the 5 s step and the countdown delta, the clamp
and limit haptic at both bounds, no flicker under fast rotation, Crown
inertness mid-morph, the button↔footer cross-fade, the superset fan-out, the
next rest starting at the new duration, and kill/relaunch recovery. Those runs
are also what surfaced both rejected layouts above.

⚠️ **None of it has automated coverage.** The write path
(`adjustRestDuration` → `commitRestDurationAdjustment` → `updateRestTime`,
including the superset fan-out) is verified by hand only — the watch view model
is not in the `GymStreakTests` target, so a regression here would be silent.
The scope prompt's revert (`applyRestAdjustmentScope` →
`preAdjustmentRestTimes`) sits on the same path and has the same gap.

**Scope prompt — fully verified on device 2026-08-11** at 41 mm and 46 mm: the
1.2 s arming and 3 s life, the caption↔row hand-off, both scopes (including the
next rest's value), the superset revert, re-arming by a second rotation,
Skip/Minimize staying reachable through it, and the German labels. The watch
target builds and the 438-test `GymStreakTests` suite passes.

**Pill stepper (ticket 03) — verified by manual pass 2026-08-11.** The long press
opens it and tap-to-expand still fires next to it (the documented-fragile
gesture pair held), the drawn pill does not move as it grows, and the ± halves
respond **even though `−15` is drawn entirely outside its host's layout box** —
which settles the hit-testing question that section raised. The watch target
builds and `GymStreakTests` (438) passes.

Two things the pass did not report on, so treat them as open: which case sizes
were exercised (the width is tiered 136/132/126/116 across 49/45 · 41 · 40 mm)
and the German accessibility labels. As with the rest of this feature there is
**no automated coverage** — XCUITest cannot rotate the Crown, and the pill still
has no accessibility identifier, so a UI test would have to reach it by
coordinate.

**Small cases (40 mm) — fixed 2026-08-11.** That pass had found the rest-timer
screen as a whole too cramped below 41 mm: the metrics row, the caption, the
44 pt digits and the button row filled it before any editing chrome arrived, and
the Minimize/Skip row was laid out off the bottom edge. The cause was not this
row — it was that the whole screen used one set of fixed point values authored
for 41 mm and up, with no tier below it. Resolved by adding the `xSmall`
(40/38 mm) column to `WorkoutScreenMetrics` and reading this view's five
constants from it (see "The vertical budget"), plus `lineLimit(1)` +
`minimumScaleFactor(0.6)` on the Skip label — German "Überspringen" is more than
twice the length of "Skip" and only has half the row to live in, so it wrapped
to two lines and grew the row into the adjustment footer drawn over the same
slot. Verified on the 40 mm simulator in de-DE, and guarded by
`GymStreakWatchUITests.testControlsStayOnScreenOnSmallestCase`, which asserts
the Skip button's frame is fully inside `app.frame`.

## Architecture: one owner, not one per screen

`WorkoutRestTimerOverlay` is mounted **once**, by `ActiveWorkoutView`, as a
sibling of the `NavigationStack` inside the same `ZStack` that already hosted the
large timer.

Why this matters (all three were real problems before 2026-07-25):

1. **The vertical `TabView` keeps neighbouring pages alive.** The exercise list,
   metrics page and controls page each declared their own compact timer (the
   since-deleted watch `CompactRestTimer`), so two or three copies could be
   mounted simultaneously.
2. **A pushed destination covers view-tree content below it.** The set editor
   therefore needed a *fourth*, differently designed copy
   (`RestTimerMinimizedPill` in its top-trailing accessory slot) just to be
   visible while pushed. As a sibling of the `NavigationStack`, the overlay now
   draws — and hit-tests — above the pushed set editor and its toolbar.
3. **A morph needs one coordinate space.** Large and minimized must live in the
   same view tree for a shared-namespace (`matchedGeometryEffect`) transition;
   per-screen copies made that impossible.

### Placement

Positioning is **safe-area anchored** — `.frame(maxWidth: .infinity,
maxHeight: .infinity, alignment: .topTrailing)` around the pill — plus two
constants on `WorkoutRestTimerOverlay` that reproduce the set editor's tuned
2026-07-24 position on every screen:

| Constant | Value | Why |
|----------|-------|-----|
| `trailingInset` | 10 | Matches the set editor's content inset (8pt screen padding + 2pt top-zone padding), so the pill's right edge lands exactly where it used to. |
| `baselineLift` | 12 | The safe area starts at the "Exercise X / Y" label. Sitting flush at the safe-area top puts the pill **on top of the segment progress bar**. Lifting it 12pt reproduces the old rule "pill bottom = that label's text baseline": it overhangs upward into the free status-bar space beside the clock instead of crowding the bar. |

That replaces the earlier `alignmentGuide(.firstTextBaseline) { $0[.bottom] }`
trick, which only worked inside `WorkoutTopProgressView`'s label row. Anything
that repositions the pill must also compensate for
`RestTimerMinimizedPill.touchInset` (below), which pads the view's layout box
beyond the drawn pill.

The expanding frame is layout-only: it has no background and no `contentShape`,
so it never swallows taps meant for the screen underneath.

### Touch target

The drawn pill is only ~22pt tall — well under a comfortable watch touch target,
and taps beside the digits missed it entirely (only the chevron end felt
reliable). `RestTimerMinimizedPill` therefore applies
`.padding(RestTimerMinimizedPill.touchInset)` (8pt on every side) **between its
chrome and its `contentShape(Rectangle())`**, so the tap/long-press region is
~16pt wider and taller than the pill without changing what is drawn. The
overlay's frame and offsets add that inset back so the visible position is
unaffected.

### Screens make room, the pill does not move

One pill in one position is the rule; where a screen has no free space at that
position, **the screen reserves it** rather than the pill relocating:

- **Set editor** — already has an empty top-trailing slot by design (it used to
  hold the elapsed-time label, which is hidden while the pill is up).
- **Exercise list** — starts with a full-width progress card at the safe-area
  top, so the pill landed on the progress ring. `ExerciseListView` now applies a
  `safeAreaInset(edge: .top)` of `restTimerSlotHeight` (16pt, animated) *while
  the timer is minimized*. It still declares no timer of its own — it only frees
  space for the overlay's.
- **Metrics / controls** — empty up there; nothing needed.

Rejected: giving each screen its own pill position (via preference-key anchors).
The carousel list is dense at every anchor, so it would need a reserved slot
anyway — the plumbing buys nothing, and per-screen positions would fight ticket
02's morph.

The tab pages did lose their old full-width top *banner*, which pushed content
down by its whole height; the reserved slot is much smaller because the pill
overhangs upward into the status-bar strip.

Both halves of that reservation live on `WatchRestTimerMorph`, not on the list
(folded there in ticket 03, which is why the coupling is at least visible now):

- `reservedSlotHeight` (16) — derived from the overlay's `baselineLift` (12) plus
  the pill's height; a screen with no free top-trailing slot frees exactly this.
- `presenceAnimation` (`.easeInOut(duration: 0.25)`) — the curve the timer
  appears/disappears on. The reserved slot **must** animate on the same curve or
  the pill and the space it needs move out of step.

⚠️ Still implicit: the derivation of `reservedSlotHeight` from `baselineLift` is
arithmetic no compiler checks. Changing the lift means re-deriving the slot.

## The large↔minimized morph

Pressing **Minimize** does not cross-fade the two states: the large timer
visibly **shrinks and travels** into the pill's top-trailing position in one
continuous motion, and tapping the pill reverses the same motion. The countdown
keeps running and stays readable throughout.

### Shared vocabulary

Unlike the iOS timer there is no ring to morph, so the shared elements are:

| Shared element | Large state | Minimized state |
|----------------|-------------|-----------------|
| **Progress surface** (`WatchRestTimerMorph.surfaceID`) | the opaque, screen-filling gradient panel that drains bottom-up | the pill's card (`.ultraThinMaterial` + hairline border) |
| **Countdown digits** (`WatchRestTimerMorph.digitsID`) | 44pt rounded bold | 13pt rounded medium |

Everything else — the "REST" caption, Minimize/Skip buttons, the HR/kCal and
elapsed-time rows, the pill's own draining capsule and chevron — is **non-shared
chrome** that simply cross-fades with the surrounding `.transition(.opacity)`.

The pill's *card* (not its inner capsule bar) is the small half of the surface:
matching the card means the panel lands exactly on the pill's outline, and the
inner bar cross-fades inside it.

### Implementation rules

Both states are branches of `WorkoutRestTimerOverlay`'s `content`, tagged in a
`@Namespace` the overlay owns. Reused from the iOS morph (`rest-timer-ui.md`),
which learned them the hard way:

1. **One size-agnostic shape, drawn identically by both states.** Large panel and
   pill card are both a `RoundedRectangle(cornerRadius: 18, style: .continuous)`,
   so only the *frame* has to interpolate. At full-screen size an 18pt radius is
   much smaller than the watch display's own corner radius, so the panel still
   covers every visible pixel — that is what allows the same shape at both ends.
2. **No hard `.frame` between the effect and the shape.** The effect must own the
   size proposal; a frame in between pins the size and degrades the morph to a
   move plus a cross-fade. The pill's surface therefore lives in `.background`
   (it inherits the pill's frame and may draw far outside it while flying).
3. **The digits match on `properties: .position` only — never `.frame`** — and
   carry `.fixedSize()` + `.contentTransition(.identity)`.
   `matchedGeometryEffect` interpolates position and size but never font size, so
   frame-matching would render each label inside the *other* state's box and make
   the digits re-lay-out on every animation step. Position-only matching moves
   them without touching their size proposal; `.fixedSize()` guarantees the
   intrinsic size, and `.contentTransition(.identity)` stops a digit change that
   lands mid-morph from being animated by the spring. Both use `anchor: .center`,
   so the two differently-sized labels match on the same conceptual point.
   True glyph interpolation would need a manually animated font size and was
   judged not worth it.
4. **`.geometryGroup()` on each state's container.** It resolves that subtree's
   geometry as one unit before the parent pushes changes down — relevant here
   because the sibling `NavigationStack` pushes and pops the set editor and the
   vertical `TabView` re-lays-out its pages while the morph runs.
5. **The large state keeps `.zIndex(1)`**, so it stays above the pill for the
   whole cross-fade and minimizing reads as one object shrinking into the corner
   rather than the pill popping in front of it.
6. **The large timer has no opaque background of its own any more.** The screen
   is covered by the progress surface, which is what makes the workout screen
   *reveal itself* progressively as the panel shrinks.
7. **Both branches keep the default `isSource: true`.** Binding it explicitly to
   the incoming state is not possible here: a view removed by a transition is not
   re-evaluated, so the outgoing branch would keep its stale `isSource` value.
   With exactly one branch mounted per state this is the supported pattern; the
   two `.transition(.opacity)` blocks do keep both mounted for the length of the
   spring, so **if a "multiple inserted views … have `isSource: true`" warning or
   a geometry jump ever appears on device**, the fallback is to restructure so
   both states are always mounted and drive `isSource` from the flag.
8. **Rapid re-toggles are guarded — by the wall clock, not by an animation
   completion.** `WorkoutRestTimerOverlay.setMinimized(_:)` records
   `lastMorphStart` and drops further *user* toggles for one
   `WatchRestTimerMorph.response` (0.42s). Interrupting an in-flight
   matched-geometry transition is a documented source of ghosting and of an
   `AttributeGraph precondition failure` crash
   ([Apple Developer Forums 681038](https://developer.apple.com/forums/thread/681038)).

   **Rejected (it shipped broken once): the iOS-style
   `withAnimation(_:completionCriteria:.logicallyComplete) { … } completion: { … }`
   flag.** On watchOS the completion fired for the *minimize* but not for the
   following *expand*, so the flag stayed set and every subsequent minimize was
   silently swallowed — the timer could be minimized exactly once per rest, and
   the button then appeared dead. Reproduced deterministically: with the
   completion-based guard a three-round minimize/expand UI test fails rounds 2
   and 3; with the time-boxed guard all three pass. Do not reintroduce a guard
   whose release depends on an animation callback firing.
9. **State-driven changes bypass the guard by construction.** Unlike iOS, the
   watch keeps `isRestTimerMinimized` / `isResting` in the view model, so a rest
   being skipped, elapsing, or the next one starting reaches the overlay directly
   and can never be swallowed — the large overlay cannot get stuck open with no
   running timer. Those paths animate through the implicit
   `.animation(_:value:)` modifiers on the overlay's body (the view model must
   not import SwiftUI to wrap them itself); user toggles additionally run inside
   the matching explicit transaction, which is what releases the guard.

### watchOS research findings (2026-07-25)

Researched before implementing, because watchOS availability differs from iOS:

- **`matchedGeometryEffect` is fully available on watchOS** (via
  `MatchedGeometryProperties`, watchOS 7.0+) and is the only documented
  mechanism for "two mutually exclusive layouts in one tree, animated as one
  object".
- **`geometryGroup()` — watchOS 10.0+**;
  **`withAnimation(_:completionCriteria:_:completion:)` and
  `AnimationCompletionCriteria` — watchOS 10.0+**. There is no
  `View.animation(_:completionCriteria:)` modifier; completions come only from
  `withAnimation` or `Transaction.addAnimationCompletion`.
- **Rejected: `matchedTransitionSource` + `.navigationTransition(.zoom(sourceID:in:))`.**
  Both *are* available on watchOS 11+, but they animate a **navigation
  push/present**, which would mean turning the pill into a navigation source and
  the large timer into a pushed destination — reintroducing the presentation
  boundary ticket 01 removed and fighting the single-coordinate-space design.
  Same verdict as iOS.
- **Rejected: `GlassEffectContainer` / `.glassEffect()`** (watchOS 26+) — it
  merges concurrently-visible glass shapes, it does not reposition-and-resize one
  logical panel between two layouts. There is no public `MorphTransition` type.
- **Known watchOS caveats (Apple Developer Forums, no Apple fix):** matched
  geometry can stutter *on device only* when the animated views sit inside a
  `NavigationStack` ([756174](https://developer.apple.com/forums/thread/756174));
  it glitches when a matched pair spans the pages of a paged `TabView`
  ([764672](https://developer.apple.com/forums/thread/764672)), and flickers when
  the paired page holds a `List`
  ([744021](https://developer.apple.com/forums/thread/744021)); it can briefly
  "pop" instead of animate right after a push/pop cycle
  ([719835](https://developer.apple.com/forums/thread/719835)).
  **Every reported configuration has one matched side inside the `TabView` pages
  or inside the pushed destination.** Ours has both sides in the overlay, a
  sibling of the `NavigationStack` — which is exactly why ticket 01's
  consolidation was a precondition. Rule of thumb: never move one of the two
  states back into a tab page or a navigation destination.
- Sources: [`MatchedGeometryProperties`](https://developer.apple.com/documentation/swiftui/matchedgeometryproperties),
  [`geometryGroup()`](https://developer.apple.com/documentation/swiftui/view/geometrygroup()),
  [`withAnimation(_:completionCriteria:_:completion:)`](https://developer.apple.com/documentation/swiftui/withanimation(_:completioncriteria:_:completion:)),
  [`ZoomNavigationTransition`](https://developer.apple.com/documentation/swiftui/zoomnavigationtransition),
  [SwiftUI Lab — matchedGeometryEffect](https://swiftui-lab.com/matchedgeometryeffect-part1/).

## Components

| Component | File | Role |
|-----------|------|------|
| `WorkoutRestTimerOverlay` | `GymStreakWatch Watch App/Views/WorkoutRestTimerOverlay.swift` | The single owner: picks large vs. minimized, positions the pill, owns the morph `@Namespace`, the wall-clock re-toggle guard (`lastMorphStart`) and `setMinimized(_:)`. |
| `WatchRestTimerMorph` | same file | Constants shared by both states and by screens that make room: the two matched-geometry ids, the surface corner radius, the morph spring, `presenceAnimation`, `reservedSlotHeight`. |
| `ActiveWorkoutView` | `GymStreakWatch Watch App/Views/ActiveWorkoutView.swift` | Mounts the overlay as a sibling of the `NavigationStack` in its root `ZStack`. |
| `ExerciseListView` | `GymStreakWatch Watch App/Views/ExerciseListView.swift` | Reserves the pill's slot via `safeAreaInset(edge: .top)` (`WatchRestTimerMorph.reservedSlotHeight`) while resting; declares no timer. |
| `RestTimerLargeView` | `GymStreakWatch Watch App/Views/RestTimerLargeView.swift` | Large state; takes the morph namespace and tags the panel + digits. Owns `adjustmentBaseline` (the flag for "an adjustment is on screen") and `adjustmentScope` (the scope prompt's selection, `nil` while the row is off screen), and nothing else about the Crown. |
| `RestDurationCrownAdjustment` | `GymStreakWatch Watch App/Views/RestDurationCrownAdjustment.swift` | `ViewModifier` carrying the whole Crown state machine: detent binding, focus, limit haptic, animation throttle, and the single task that runs the tail (chrome out → scope prompt in → out). Applied by the large state via `.restDurationCrownAdjustment(isEnabled:baseline:scope:)`. |
| `RestAdjustmentCaption` / `RestAdjustmentFooter` / `RestAdjustmentChrome` / `RestScopeRow` | `GymStreakWatch Watch App/Views/RestDurationAdjustmentChrome.swift` | The editing treatment — delta badge over the caption, tick track + `old → new` line cross-faded into the Minimize/Skip slot, and the "This rest / All sets" prompt that follows. Nothing here has a slot of its own; see "The vertical budget". |
| `RestTimerMinimizedPill` | `GymStreakWatch Watch App/Views/RestTimerMinimizedPill.swift` | Minimized pill; takes the morph namespace and tags its card + digits. Owns the pill's two gestures and, while its stepper is open, the Crown state machine (detent binding, limit haptic, the 3 s collapse, the commit). |
| `RestPillStepper` / `WatchRestPillStepper` | `GymStreakWatch Watch App/Views/RestPillStepper.swift` | The grown pill's presentation (`−15 · 1:45 · +15`) and its constants: tap step, life, spring, hit side. No state of its own. |
| `RestLimitHaptic` | `…/RestDurationCrownAdjustment.swift` | The once-per-arrival bound haptic, shared by both adjustment paths. |
| `WatchWorkoutViewModel` | `GymStreakWatch Watch App/ViewModels/` | Timer state and actions (`startRestTimer`, `skipRest`, `minimizeRestTimer`, `expandRestTimer`). |

### File layout

Three files, split along the state seam — one per state plus the owner:

- `WorkoutRestTimerOverlay.swift` — the owner (`WorkoutRestTimerOverlay`) and the
  shared constants (`WatchRestTimerMorph`). Nothing else may mount a rest timer.
- `RestTimerLargeView.swift` — the large state only.
- `RestTimerMinimizedPill.swift` — the minimized pill only.

The two state views know nothing about each other; everything they share travels
through `WatchRestTimerMorph` and the namespace the overlay passes down.

The Crown adjustment adds two more files rather than growing the large state
past the file-size cap: `RestDurationCrownAdjustment.swift` (input and timing)
and `RestDurationAdjustmentChrome.swift` (presentation). They meet only at
`adjustmentBaseline` and `adjustmentScope`, which the large state owns and hands
to both.

The pill's stepper follows the same split for the same reason:
`RestPillStepper.swift` is presentation plus constants, and the input/timing
state machine stays in `RestTimerMinimizedPill.swift`. It is **not** a
`ViewModifier` like the large state's — the ± buttons have to call into the same
functions the Crown does, which a modifier cannot hand out.

### Deleted variants (2026-07-25)

Five earlier designs are gone; recover them from git history (`4fe775c`) if ever
needed:

| Deleted | Where it lived | Why |
|---------|----------------|-----|
| `CompactRestTimer` (watch) | `Views/RestTimerView.swift` | A slim top-banner design; only `ExerciseSetView` ever mounted it. **Note:** the iOS target has an unrelated type of the same name (`Presentation/Views/Workout/CompactRestTimer.swift`) which is live and untouched. |
| `ShrinkingRestTimer` | `Views/RestTimerView.swift` | Older, `GeometryReader`-based pill; superseded by `RestTimerMinimizedPill`. Unreferenced. |
| `RestTimerView` (commented out) | `Views/RestTimerView.swift` | The original ring-based large timer, commented out long before this cleanup. |
| `ExerciseSetView` (+ `ProgressRing`, `Array[safe:]`) | `Views/ExerciseSetView.swift` | An entire unused set screen — `FullScreenSetEditorView` is the live one. Its only remaining role was being the last `CompactRestTimer` call site. |
| `RestTimerEditorSheet` | `Views/RestTimerEditorSheet.swift` | A 140-line file whose only live statement was `import SwiftUI`. |

The `New…` prefixes on the two survivors existed purely to distinguish them from
those variants, so they were dropped in the same pass.

## Open follow-ups (carried out of the ticket set, none blocking)

The `.scratch/watch-rest-adjust/` tickets are archived; these are the items they
recorded that were never applied, kept here so they are not lost with them.

- **The watch write path has no automated coverage.** `WatchWorkoutViewModel` is
  not in the `GymStreakTests` target, so `adjustRestDuration` →
  `commitRestDurationAdjustment` → `updateRestTime` / `restoreRestTimes`,
  including the superset fan-out and the two buffer fixes above, are verified by
  hand only. A regression there would be silent. This is also why the
  finalization-freeze bug reached a device.
- **`RestTimerMinimizedPill` observes the whole workout view model.** Ticket 03
  gave it an `@EnvironmentObject` on `WatchWorkoutViewModel` — which owns the
  rest timer *and* the `@Published var exercises` tree — so every unrelated
  publish (set completion, structural edit, HealthKit metric) re-evaluates a view
  that sits above every workout screen for the length of a rest. Fix: keep it
  value-driven like `onExpand` already is — have `WorkoutRestTimerOverlay`, which
  already observes the model, pass `restDuration` / `canAdjust` in and hand the
  two mutations down as closures.
- **Three files are over the 300-line convention:** `RestTimerMinimizedPill`
  (347, the crown seeding/echo suppression, clamping, haptics and collapse task
  all landed in the view struct — extract them into a `ViewModifier` beside
  `RestDurationCrownAdjustment`), `RestTimerLargeView` (316) and
  `WatchWorkoutViewModel` (1682). The view model's rest cluster cannot move to a
  `+RestAdjustment` extension: `pendingRestDuration` and `preAdjustmentRestTimes`
  are stored properties, and splitting the methods from them would force both to
  `internal`.
- **Never individually confirmed for the pill stepper (ticket 03):** which case
  sizes were exercised (the width is tiered 136/132/126/116 across 49/45 · 41 ·
  40 mm) and the German accessibility labels.
- **Exercise-level fields are not mirrored into the main context.** `order`,
  `supersetId` and `supersetOrder` are written on retained rows by the structural
  merge and are exposed to the same conflict-loss mechanism that swallowed rest
  (see `docs/watch-sync.md`). Not observed in the field; left to the structural
  feature rather than bolted on here.

## Verification

Verified on an Apple Watch Series 11 (46 mm) simulator (watchOS 26.5) with a
throwaway XCUITest driving a real workout (test since deleted):

- exactly one pill, at the same top-trailing position, on the exercise list,
  metrics page, controls page and the pushed set editor — clear of the system
  clock, of the set editor's segment progress bar, and of the list's progress
  card (whose reserved slot collapses again the moment the rest ends);
- tap-to-expand works from the pill's **body** (over the digits, not just the
  chevron), from a tab page **and** while the set editor is pushed (proving the
  overlay hit-tests above the pushed destination);
- long-press-to-skip removed the timer entirely (that gesture was reassigned to
  the inline stepper on 2026-08-11 — see "The gesture reassignment");
- the countdown decremented continuously across navigation (115 → 103 → …).

Note for future work: the pill is a plain `HStack` with no accessibility label or
identifier — UI tests have to reach it by coordinate. On a 46mm screen
(208×248pt) its centre is at the normalized offset `(0.745, 0.242)`. The large
timer's minimize button is queryable as
`app.buttons["rectangle.compress.vertical"]`; the Skip button by its label
("Skip" / "Überspringen" — note the minimize button's *German* accessibility
label also contains "Überspringen", so match Skip on equality, not `CONTAINS`).

### Morph (2026-07-25)

Verified on the same simulator with a second throwaway XCUITest (also deleted)
that drove a real workout through the whole morph matrix:

- a screenshot captured **mid-flight** shows the intended motion: the large panel
  shrunk to a rounded rectangle travelling toward the top-trailing corner, the
  44pt digits travelling with it, the pill fading in at its final position, and
  the set editor revealed behind the shrinking panel — i.e. one object changing
  size and place, with the chrome cross-fading;
- minimize hides the large timer and shows the pill, tapping the pill restores
  the large timer (both directions asserted);
- rapid re-toggling (minimize + two immediate pill taps + minimize) left exactly
  one state mounted, no ghost, and the app running;
- **Skip on the large timer closes it**, and a rest **left to elapse while
  minimized** closed the overlay on its own — the re-toggle guard swallows
  neither;
- the run produced **no** "multiple inserted views … have `isSource: true`"
  warning and no AttributeGraph failure;
- **three consecutive minimize/expand round trips** all succeed. This case was
  added after the first build on device could be minimized only once (see the
  rejected completion-based guard in rule 8); the earlier probe asserted only
  that rapid toggling did not crash, which is why it missed the regression.

**On a physical Apple Watch (2026-07-25):** the morph animates as intended in
both directions, and repeated minimize/expand cycles within one rest work — the
device run is what surfaced the stuck-guard bug in rule 8, and confirmed the
time-boxed guard fixes it. Still not exercised on device: pushing or popping the
set editor *while a morph is in flight*, and paging the vertical `TabView`
mid-morph. Those are precisely the configurations the forum reports call out as
device-only, so check them first if jank ever appears.

## History

- **2026-07-24** — elapsed time and the rest pill were moved out of the watch
  toolbar into the set editor's top-trailing accessory so they stop colliding
  with the system clock.
- **2026-07-25** — the four per-screen minimized timers were replaced by this
  single overlay owned by `ActiveWorkoutView` (ticket
  `.scratch/watch-rest-timer-morph/issues/01`). No morph yet — the large↔pill
  switch is still a crossfade; the shared-namespace morph is ticket 02.
  Three follow-up fixes the same day, after the first builds on device: the pill
  had dropped onto the segment progress bar (fixed by `baselineLift`), only its
  chevron end reacted to taps (fixed by `touchInset`), and it floated over the
  exercise list's progress ring (fixed by the list's reserved slot).
- **2026-07-25** — the large↔pill switch became a continuous morph (ticket
  `.scratch/watch-rest-timer-morph/issues/02`): a shared progress surface and
  shared countdown digits tagged with `matchedGeometryEffect` in a namespace
  owned by `WorkoutRestTimerOverlay`, plus the re-toggle guard. The large timer
  lost its own opaque background (the progress surface is the opaque layer now)
  so the workout screen is revealed as the panel shrinks.
- **2026-07-25** — cleanup (ticket `.scratch/watch-rest-timer-morph/issues/03`):
  the five dead variants above were deleted, the 649-line `RestTimerView.swift`
  was split into `RestTimerLargeView.swift` + `RestTimerMinimizedPill.swift`, the
  two survivors lost their now-meaningless `New…` prefixes, and
  `ExerciseListView`'s reserved-slot constants moved onto `WatchRestTimerMorph`.
  No behaviour change.
- **2026-08-11** — the minimized pill gained the inline `−15 · 1:45 · +15`
  stepper on long press (ticket `.scratch/watch-rest-adjust/issues/03`), which
  cost the pill its long-press-to-skip and introduced the explicit
  `WatchRestCrownOwner` hand-over. Also the first use of
  `\.isRestPillStepperOpen` — the workout screens now know when the pill has
  grown across their top row.
- **2026-08-10** — the Digital Crown became able to change a running rest's
  duration (ticket `.scratch/watch-rest-adjust/issues/01`), followed by the
  "This rest / All sets" scope prompt (ticket `…/02`, verified on device
  2026-08-11), which turned the all-sets write from the only behaviour into the
  confirmed default. That pass also established that this screen does not yet
  work at ≤ 40 mm — a pre-existing design gap, now recorded above.
