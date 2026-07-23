# Watch — Toolbar bar-button constraint warnings (watchOS 26)

Target: **watchOS only** (`GymStreakWatch Watch App`). No iOS changes.

## Symptom
With the Xcode debugger attached, the console logs `Unable to simultaneously
satisfy constraints` and recovers by breaking
`PUICBarButtonItemView.width == PUICBarButtonItemView.height`. A
`CoreUI: CUIThemeStore: No theme registered with id=0` line often prints at the
same instant (a benign CoreUI asset-theme miss, not actionable).

## Root cause (shared mechanism)
watchOS renders navigation-bar buttons through the private **PepperUICore**
framework (`PUIC*`). A SwiftUI `ToolbarItem` is bridged into a
`PUICBridgedButtonBarButton` via `SaltUICore.BarButtonRepresentable`. The system
installs a **required** constraint that bar buttons are square
(`PUICBarButtonItemView.width == .height`) and pins the item view to all four
edges of the bridged button, so the representable host's width flows straight
into the button's width.

When the host width resolves to **0** while the height is the standard **37 pt**,
`0 == 37` is impossible and AutoLayout breaks the square constraint. So every
instance of this warning traces to a **zero-width bridged bar button**. There are
two distinct sources in the active-workout flow.

---

## Source 1 — Empty trailing toolbar item in the set editor — **FIXED**
`FullScreenSetEditorView` declares a `.topBarTrailing` `ToolbarItem` whose content
is a minimized rest timer **or** an elapsed-time chip. `elapsedTimeString` is
`nil` until the first HealthKit elapsed-time tick, so on entry (and any
non-resting state before that tick) the item's inner `Group` rendered **nothing**
— a present-but-empty toolbar item became a zero-width square bar button.

**Fix:** hoist the visibility condition out of the inner `Group` up to the
`@ToolbarContentBuilder` level, so the `ToolbarItem` is **not declared at all** in
the empty state. No bar button is created, so there is no square constraint to
break. Both real states (rest timer, elapsed chip) render exactly as before; the
`.offset(y: -8)` centerline lift and framing now live on each branch's content.

File: `GymStreakWatch Watch App/Views/FullScreenSetEditorView.swift` (the
`.toolbar { … }` block).

---

## Source 2 — End-Workout confirmation dialog — **ACCEPTED (OS bug, not fixed)**
When the user taps the top-left "X" in a running workout, the
`.confirmationDialog("End Workout?", isPresented: $showEndConfirmation)` on
`ActiveWorkoutView` presents, and the warning fires. The "X" is an
`ToolbarItem(placement: .cancellationAction)` that intentionally replaces the
modal cover's auto-injected system close button so closing routes through the
confirmation (see the comment at `ActiveWorkoutView.swift` around the
`.cancellationAction` block).

### Why it is not an app bug
The `width == 0` is logged as an **`NSAutoresizingMaskLayoutConstraint`**
(`h=--&`) on the `BarButtonRepresentable` **host itself** — i.e. UIKit's synthetic
reflection of the host's actual `frame.size`, set directly to zero by **watchOS
26's presentation transition** when the dialog appears. It is not derived from our
SwiftUI content. watchOS 26's Liquid-Glass presentation system appears to treat
the triggering toolbar button as an implicit zoom-transition source and collapses
its host to width 0 mid-transition, colliding with the required square constraint.

This matches a live, unresolved watchOS/iOS 26.x regression (Apple DTS triaging
forum thread 804298; the adjacent bar-button constraint-warning class in thread
810476 is being patched across 26.x point releases). The warning is **benign** —
the system recovers by breaking the square constraint and nothing renders wrong.

### Approaches proven not to work (do not re-try)
- **`.frame(minWidth: 37, minHeight: 37)` on the button's `Image` label** —
  applied and tested; **no effect**. The zero width is set on the host frame by
  the transition, not derived from content intrinsic size, so content sizing
  cannot touch it.
- **`.topBarLeading` instead of `.cancellationAction`** — routes through the
  identical private PUIC bridge; won't change the code path. Also drops the
  modal-cancel semantics the override relies on.
- **Plain `.sheet` instead of `.confirmationDialog`** — watchOS auto-synthesizes
  its own leading bar button into sheet content (from the navigation title)
  through the same bridge, so it likely reproduces an equivalent warning for a
  system-owned button.
- **Opting out of the transition link while keeping `.confirmationDialog`** — no
  public API. `matchedTransitionSource` / `navigationTransition(.zoom(...))` exist
  only for sheet-style presentations, not `confirmationDialog`.
- **Private logging flags** (`_UIConstraintBasedLayoutLogUnsatisfiable` etc.) —
  only silence the console; they do not remove the underlying collapse.

### The only provable elimination (deliberately NOT taken)
Remove every private PUIC bar-button code path from the screen: replace the native
`.confirmationDialog` **and** the `.cancellationAction` toolbar "X" with
hand-rolled overlay views (the same `ZStack` overlay pattern as `NewRestTimerView`
/ `WatchWorkoutSummaryView`, which have no toolbar chrome). Not done because:
1. It changes the confirmation UI (native dialog chrome/animation and the nav-bar
   X become custom look-alikes).
2. Removing the `.cancellationAction` override risks the modal cover's system close
   button reappearing and dismissing directly — bypassing the End-Workout
   confirmation and leaving the HealthKit session running, a worse functional
   regression than a benign console warning.

**Decision (2026-07-23):** accept the warning as an OS bug; keep the working native
UI. Revisit when a later watchOS 26.x point release addresses the PUIC bar-button
transition regression. If a fix is ever required before then, the provable path
above is the one to take — with care to preserve "modal close routes through the
End-Workout confirmation".

## Research trail
`PUICBarButtonItemView` / `PUICBridgedButtonBarButton` / `SaltUICore.BarButtonRepresentable`
are undocumented private symbols — no citable radar. Evidence:
- Apple Developer Forums thread 804298 — confirmationDialog-in-NavigationStack-toolbar
  transition issue on Xcode 26 / iOS 26, DTS investigating, unresolved.
- Apple Developer Forums thread 810476 — `UIBarButtonItem` constraint-warning class on
  Xcode 26 / iOS 26, reportedly being patched in 26.x point releases.
- Apple Developer Forums thread 658222 — watchOS sheets auto-synthesize a toolbar bar
  button from the navigation title (why a plain `.sheet` would reproduce it).

## Files touched
- `GymStreakWatch Watch App/Views/FullScreenSetEditorView.swift` — Source 1 fix
  (conditionally omit the trailing toolbar item).
- `GymStreakWatch Watch App/Views/ActiveWorkoutView.swift` — Source 2 left as-is
  (native `.confirmationDialog` + `.cancellationAction` X unchanged).
