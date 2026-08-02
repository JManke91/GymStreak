# Rest Timer UI (iOS)

## Overview

During an active workout the iOS app shows a rest countdown in two states:

- **Compact** (`WorkoutRestBar`) — **the default state.** A bar pinned above the
  workout's action buttons with a small progress ring, the remaining time, a
  fill that grows as the rest runs down, and **+30s** / **Continue** buttons.
  Tapping the bar itself expands.
- **Large** (`RestTimerView`) — a centered circular countdown ring, the remaining
  time, an optional reminder-warning banner, and **Minimize** / **Skip** buttons.
  **Opt-in since the 2026-07-31 active-workout redesign** — see below.

Both states live inside `ActiveWorkoutView` and are driven by the same
`WorkoutViewModel` timer state (`isRestTimerActive`, `restTimeRemaining`,
`restDuration`, `restTimerReminderWarning`).

This document covers the **presentation/interaction** of the rest timer. For the
local-notification side (scheduling, authorization, deadline handling) see
`rest-timer-notifications.md`.

> Scope: **iOS target only.** The watchOS rest timer is a separate implementation
> (already overlay-based) — see `watch-rest-timer-ui.md`.

## Behavior

- When a rest starts (`viewModel.isRestTimerActive` flips to `true`), the **bar**
  appears. **The large timer no longer opens automatically** (changed
  2026-07-31 with the active-workout redesign — see
  `active-workout-redesign.md`): rest used to take over the screen the moment a
  set was checked off, which blocked logging and correcting values while
  resting. The bar is now the resting state and the large timer is opt-in.
- **Tapping the bar** reverses the morph and opens the large timer.
- **Minimize** collapses the large timer back to the bar — the countdown ring
  and time label *shrink and travel* into the bar position in one continuous
  morph (see "The large↔compact morph" below).
- **+30s** on the bar calls `WorkoutViewModel.extendRestTimer(by: 30)`, which
  restarts the timer at `restTimeRemaining + 30`. Restarting (rather than
  mutating the deadline in place) is what keeps the local notification, the Live
  Activity and the persisted deadline consistent with the new end time.
- **Continue** on the bar and **Skip** in the large timer both call
  `stopRestTimer()`; the large timer then closes.
- The bar is shown **only** while a rest is active *and* the large timer is not
  shown (`isRestTimerActive && !showingRestTimerOverlay`).
- The countdown keeps running and updating throughout the morph — both states
  read the same view-model values, and both are briefly mounted during the
  transition.

The large↔compact switch is a single `@State showingRestTimerOverlay` toggle. Every switch
goes through `ActiveWorkoutView.setRestTimerExpanded(_:force:)`.

## Structure / architecture

Both states are rendered inside `ActiveWorkoutView`'s own view tree (the same
coordinate space), not in a separate presentation context:

- The **compact** bar sits in the `.safeAreaInset(edge: .bottom)` stack, directly
  above `WorkoutFooterActions`. (Before 2026-07-31 it was a top-inset banner,
  `CompactRestTimer`, now deleted.)
- The **large** timer is an `if showingRestTimerOverlay { … }` **full-screen
  overlay** — the last child of the top-level `ZStack`, with an opaque
  `DesignSystem.Colors.background` behind it, `.transition(.opacity)`, and
  `.zIndex(1)` so it layers above the workout content.

State transitions (`onExpand`, `onDismiss`, the force-close when the timer stops) all funnel
through `setRestTimerExpanded(_:force:)`, which runs a single
`withAnimation(RestTimerMorph.animation)` transaction so exactly one variant is
mounted at a time.

## The large↔compact morph

The shared elements — the circular progress ring and the remaining-time label —
are tagged with `matchedGeometryEffect(id:in:)` in a `@Namespace` owned by
`ActiveWorkoutView` and passed into both states. Everything else (title, caption,
buttons, banner background, reminder warning) is non-shared chrome that simply
cross-fades via `.transition(.opacity)`.

### Implementation rules learned the hard way

These are the non-obvious constraints; changing any of them breaks the morph:

1. **The ring must be size-agnostic.** `RestTimerRing` has *no* intrinsic frame:
   it fills the proposed size and derives its stroke width from the diameter
   (`strokeRatio = 0.075` → 12pt at 160pt, ~2.4pt at 32pt). A hard-coded ring
   size or line width cannot interpolate.
2. **`matchedGeometryEffect` goes *inside* the `.frame`**, i.e.
   `RestTimerRing(...).matchedGeometryEffect(...).frame(width:height:)`.
   The effect overrides the size *proposal* passed down to its child; a hard
   `.frame` placed between the effect and the ring pins the ring's size, and the
   morph degrades to a move-only animation with a cross-fade.
3. **The time label matches on `properties: .position` — never `.frame`, and it
   carries `.fixedSize()` + `.contentTransition(.identity)`.**
   `matchedGeometryEffect` interpolates position and size, never font size
   (`MatchedGeometryProperties` has no font component), so the two labels keep
   their own fonts (`.largeTitle` rounded bold vs. `.onyxNumber`) and cross-fade
   while travelling.
   The first implementation matched `.frame`, and the countdown digits visibly
   **wiggled and snapped as the spring settled**: frame matching forces each
   label to render inside the *other* state's box — a largeTitle string squeezed
   into the ~40pt bar box and vice versa — so the text re-laid out on every
   animation step, and the parent `VStack`/`HStack` re-laid out with it.
   Position-only matching moves the label without ever touching its size
   proposal; `.fixedSize()` guarantees the intrinsic size regardless of what the
   container proposes, and `.contentTransition(.identity)` keeps a digit change
   that lands mid-morph from being animated by the morph's spring.
   Forcing true glyph interpolation would need a manually animated `CGFloat` font
   size; that was judged not worth the complexity for a 0.45s spring on a digit
   string.
4. **`.geometryGroup()` on each state's container** (the large `ZStack` holding
   ring + label, and the rest bar's root). It makes each subtree resolve
   its geometry as one unit before the parent pushes changes down, which is
   Apple's prescribed fix for matched-geometry jank next to a scrolling
   container — relevant here because the rest bar lives in a
   `.safeAreaInset` above a `ScrollView`, whose content offset can otherwise be
   misread mid-animation.
5. **Rapid re-toggles are guarded.** `setRestTimerExpanded(_:force:)` sets
   `isRestTimerMorphing` and ignores further user toggles until the
   `withAnimation(_:completion:)` (iOS 17+) completion fires. Interrupting an
   in-flight matched-geometry transition is a documented trigger for ghosted /
   duplicated views and an `AttributeGraph precondition failure: invalid value
   type for attribute … saw ViewTransform, expected Phase` crash
   ([Apple Developer Forums thread 681038](https://developer.apple.com/forums/thread/681038)),
   still reported through iOS 17–26 with no confirmed fix.
   The `force: true` path exists so a **state-driven** close (the timer being
   skipped or elapsing) is never swallowed by the guard — otherwise the large
   overlay could get stuck open with no running timer.
6. **Both branches keep the default `isSource: true`.** That is the supported
   pattern when exactly one variant is mounted at a time; the "multiple inserted
   views … have `isSource: true`" warning only applies when two live sources
   share an id simultaneously. Keeping the matched views shallow inside their
   branches also reduces exposure to the AttributeGraph bug above.
   *Caveat:* the two `.transition(.opacity)` blocks do keep the outgoing and
   incoming variant mounted together for the length of the spring, so the
   ambiguity is not purely theoretical. **If a "multiple inserted views …" log
   warning or a geometry jump ever shows up on device**, the fix is to bind the
   flag explicitly — `isSource: showingRestTimerSheet` on the large ring/label and
   `isSource: !showingRestTimerSheet` on the compact ones — which makes the
   *incoming* state the unambiguous source and the outgoing one follow it.

Cross-container matching (a `.safeAreaInset` child ↔ a sibling `ZStack` child)
is by design: matching is scoped by namespace + id, not by layout container.

### Rejected alternative: `.navigationTransition(.zoom)` + `fullScreenCover`

The iOS 18+ zoom transition (`matchedTransitionSource` +
`.navigationTransition(.zoom(sourceID:in:))`) was considered and rejected: it
only applies to a **presented** destination (full-screen cover or navigation
push), which reintroduces exactly the presentation boundary that ticket 01
removed, and it morphs the whole presented container rather than letting the
shared ring and label fly independently into an in-tree bar. It also gives no
control over the non-shared chrome. `matchedGeometryEffect` inside one hierarchy
was chosen instead.

### Research sources

- [SwiftUI Lab — matchedGeometryEffect Part 1](https://swiftui-lab.com/matchedgeometryeffect-part1/) and [Part 2](https://swiftui-lab.com/matchedgeometryeffect-part2/) (layout mechanics, `isSource`)
- [Chris Eidhof — When matchedGeometryEffect doesn't work](https://chris.eidhof.nl/post/matched-geometry-effect/) (modifier order / size proposal)
- [Apple — `geometryGroup()`](https://developer.apple.com/documentation/swiftui/view/geometrygroup%28%29)
- [Apple Developer Forums 681038](https://developer.apple.com/forums/thread/681038) (AttributeGraph crash), [785572](https://developer.apple.com/forums/thread/785572) (scroll-offset misread)

### Why an in-tree overlay instead of `.sheet` (design decision)

The large timer was **originally a bottom `.sheet`** presented with
`presentationDetents([.height(320), .medium])`. It was converted to an in-tree
overlay because `matchedGeometryEffect` — the mechanism that drives the
continuous shrink/grow morph between the large and compact states — **cannot
cross a `.sheet` presentation boundary**. Both states must live in one view
hierarchy to share a `@Namespace`.

**Deliberate tradeoff (approved):** dropping the `.sheet` also drops its
drag-to-dismiss gesture and the `.medium` detent (the "peek" at the workout
behind the timer). The **Minimize** button and **tap-to-expand** are now the only
ways to move between states. This is intentional and required for the continuous
morph. To restore the sheet behavior, revert to a
`.sheet(isPresented:) { RestTimerView(...) }` with detents.

### Consequences for `RestTimerView`

Because it is no longer inside a `.sheet`, `RestTimerView` **must not** call
`@Environment(\.dismiss)` — that would dismiss the entire `ActiveWorkoutView`.
It closes itself solely through its injected `onDismiss` closure (which routes to
`setRestTimerExpanded(false)` in `ActiveWorkoutView`).

`ActiveWorkoutView` alone owns the open/close lifecycle: its
`onChange(of: viewModel.isRestTimerActive)` force-closes the large timer when the
timer stops, so an externally-stopped timer (e.g. Skip from elsewhere) still
closes the large view. It no longer opens it — that is now user-initiated only. `RestTimerView`
deliberately has **no** `onChange` of its own — two handlers reacting to the same
state change would race.

A sheet also used to make the content behind it inert for VoiceOver; an in-tree
overlay does not, so the workout content (list, header inset and footer inset,
including the rest bar) carries `.accessibilityHidden(showingRestTimerOverlay)`.

## Components

| Component | File | Role |
|-----------|------|------|
| `ActiveWorkoutView` | `Presentation/Views/Workout/ActiveWorkoutView.swift` | Owns `showingRestTimerOverlay`, the `@Namespace`, the `isRestTimerMorphing` guard and `setRestTimerExpanded(_:force:)`; hosts the bar (bottom safe-area inset) and the large overlay (ZStack child). |
| `RestTimerView` | `Presentation/Views/Workout/RestTimerView.swift` | Large state: 160pt ring, time label, reminder warning, Minimize/Skip. |
| `WorkoutRestBar` | `Presentation/Views/Workout/WorkoutRestBar.swift` | Compact state: 32pt ring, time label, elapsed fill, +30s/Continue, tap-to-expand. Replaced `CompactRestTimer` (deleted 2026-07-31). |
| `RestTimerRing` | `Presentation/Views/Workout/RestTimerRing.swift` | The shared, size-agnostic countdown ring rendered by both states. |
| `RestTimerMorph` | `Presentation/Views/Workout/RestTimerRing.swift` | Constants shared by both states: matched-geometry ids, the two diameters, and the spring animation. |
| `WorkoutViewModel` | `Presentation/ViewModels/` | Source of truth for timer state and actions (`stopRestTimer`, `formatTime`, `restDuration`, …). |

The watchOS target has its own, separate rest timer — `RestTimerLargeView` plus the
`RestTimerMinimizedPill`, mounted by `WorkoutRestTimerOverlay` in
`GymStreakWatch Watch App/Views/`. Out of scope here; see
`watch-rest-timer-ui.md`. It reuses the rules above for its own morph (shared
shape, effect inside the frame, position-only digits, `geometryGroup()`,
re-toggle guard), but its shared vocabulary is a **progress surface** and the
digits — there is no ring on the watch.
