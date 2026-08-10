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
  expand, **long-press (0.5 s)** to skip.

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
(frames A1/A2 = idle vs. editing, C1 = 41 mm space probe). Frame B3 — long-press
on the training-time chip when no rest runs — is deliberately **not** built.

## Behavior

- A rest starts when a set is completed and that set's `restTime > 0` and it is
  not the last set (`WatchWorkoutViewModel.startRestTimer`). The large timer
  opens automatically (`isRestTimerMinimized` is reset to `false`).
- **Minimize** collapses to the pill; **tapping** the pill expands again;
  **long-pressing** the pill skips the rest (same as **Skip** on the large
  timer). Both pill gestures play a haptic. Minimize and expand are a
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

### What gets written, and why supersets are different

`WatchWorkoutViewModel.updateRestTime(for:newRestTime:)` is the **single write
path**: it takes a list of exercise ids and writes the duration to every set of
each, completed ones included. The list comes from
`restAdjustmentExerciseIDs`, captured when the rest starts:

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

### Crown ownership

The **large** state owns the Crown while it is up (it covers the whole display);
the **minimized pill** deliberately does not, so the list underneath keeps its
Crown scrolling. Ownership is additionally gated on `isMorphSettled` — Crown
input is inert while a large↔pill morph is in flight.

That flag lives on `WorkoutRestTimerOverlay` and is driven off
`viewModel.isRestTimerMinimized` changing (not off `setMinimized`), so
state-driven switches — a rest elapsing while minimized — count as a morph too.
Like the re-toggle guard it is released by the **wall clock**, never by an
animation-completion callback (see rule 8 below for what happened the one time
that was tried).

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

- **No scope choice.** The adjustment always applies to *all* sets of the
  owning exercise(s); the one-time escape hatch is a follow-up ticket.
- **No adjustment from the pill**, and none when no rest is running.
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
| `RestTimerLargeView` | `GymStreakWatch Watch App/Views/RestTimerLargeView.swift` | Large state; takes the morph namespace and tags the panel + digits. Owns `adjustmentBaseline` (the flag for "an adjustment is on screen") and nothing else about the Crown. |
| `RestDurationCrownAdjustment` | `GymStreakWatch Watch App/Views/RestDurationCrownAdjustment.swift` | `ViewModifier` carrying the whole Crown state machine: detent binding, focus, limit haptic, animation throttle, the linger before the chrome fades. Applied by the large state via `.restDurationCrownAdjustment(isEnabled:baseline:)`. |
| `RestAdjustmentCaption` / `RestAdjustmentFooter` / `RestAdjustmentChrome` | `GymStreakWatch Watch App/Views/RestDurationAdjustmentChrome.swift` | The editing treatment — delta badge over the caption, tick track + `old → new` line cross-faded into the Minimize/Skip slot. Nothing here has a slot of its own; see "The vertical budget". |
| `RestTimerMinimizedPill` | `GymStreakWatch Watch App/Views/RestTimerMinimizedPill.swift` | Minimized pill; takes the morph namespace and tags its card + digits. |
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
past the file-size cap: `RestDurationCrownAdjustment.swift` (input) and
`RestDurationAdjustmentChrome.swift` (presentation). They meet only at
`adjustmentBaseline`, which the large state owns and hands to both.

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
- long-press-to-skip removes the timer entirely;
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
