# Watch Workout Screen — Set Completion & Action Dock

## Overview
The bottom of the watch workout screen (`FullScreenSetEditorView`) is a fused action row: two round set-navigation chevron buttons flanking a glass-style Complete capsule (`CompactActionBar`). The capsule is **icon-only** (since 2026-07-24) — a single large checkmark (or an undo arrow when the displayed set is already completed) — while its translucent green fill and mini segments carry the set progress (completed sets / total). Above the row sit the weight/reps value cards with shared round +/− stepper buttons and live heart-rate/calorie metrics.

The visual design comes from a Claude Design handoff bundle: `design/gym-streak/project/Watch Final Design.html` with exact specs in `design/gym-streak/project/SwiftUI Handoff.md` (implemented 2026-07-12).

## Screen Layout (action row pinned, editing group centered)
0. **Top zone** (`WorkoutTopProgressView`, added 2026-07-12 from the Final design, handoff §4; **decoupled into two context levels 2026-07-23**): Fills the space between the toolbar (system clock only) and the stepper cluster with two stacked levels so the routine-level and exercise-level context never blur together:
   - **Routine level** (top): an uppercase `Exercise X / Y` label (`textMuted`, kerned; localized key `Exercise %lld / %lld` → de `Übung %lld / %lld`) with a **right-aligned trailing accessory on the same line** — the elapsed-time label, or the minimized rest timer while resting (relocated here from the top toolbar 2026-07-24, see "Elapsed time & rest timer" below). Below the label is the per-exercise segment bar — one segment per exercise in workout order, each a dark `segmentTrack` (#2A2A2C) capsule with a leading fill sized to that exercise's completed/total sets. The fill is **neutral gray `segmentFill` (#5C5C60), not green** — green is now reserved exclusively for the current set (its counter number and the Complete button fill), so the bar can never be misread as green "exercise progress". `WorkoutTopProgressView` is generic over the trailing accessory (`WorkoutTopProgressView<Trailing: View>`) so it stays a pure layout container and the rest timer's own buttons stay accessible; `FullScreenSetEditorView.topTrailingAccessory` builds the elapsed/rest-timer view.
   - **Exercise level** (below the bar): the current exercise name on the left and a `Set X/Y` counter on the right, where the current set number is `accentGreen` + bold and the `/total` is muted (`Text` concatenation; label from localized key `Set`). The name is a **`WatchMarqueeText`** (2026-09-01) — it scrolls its own overflow through the fixed slot rather than ellipsizing it; near-fits still just shrink via `minimumScaleFactor(0.85)`. See "Scrolling exercise name" below.
   - The earlier design showed the exercise name on top with a whole-workout completion **percent** (removed) and a green segment bar; both the percent and the `workoutProgress` init param are gone.
1. **Steppers + metrics row**: two round dark-green +/− buttons adjust the focused value card; live ❤️ BPM and 🔥 kCal metrics (`WorkoutMetricsView`, shown only when HealthKit delivers values). The +/− cluster **follows focus** — it sits on the same side as the focused card (weight = left, reps = right) and slides to the other side, past the metrics column, when focus moves, so the steppers always read as directly controlling the focused card. Restored 2026-07-12 — the glass-button redesign (`0ce2bdd`) had pinned the steppers to the left, breaking this context link.
   - **Smooth swap implementation**: the row is a `ForEach(clusterOrder, id: \.self)` over a stable `ClusterSlot` identity (`.steppers`/`.metrics`), NOT an `if/else` reorder. Keying on the slot identity (never on position) lets SwiftUI treat the focus change as a *move* and interpolate each cluster's frame into a slide; an `if/else` swap only crossfades because its branches are distinct identities. Each slot uses an equal-width `frame(maxWidth: .infinity, alignment:)` (alignment derived from focus, not row position) to hug its outer edge — this stands in for the old `Spacer`, which jitters when placed between reordered `ForEach` items. Animated with `.snappy(duration: 0.22, extraBounce: 0.05)` on `value: clusterOrder`, guarded by `accessibilityReduceMotion` (no animation when reduce-motion is on). The metrics slot is dropped from `clusterOrder` entirely until HealthKit delivers values (it then fades in as an insert; the steppers still slide correctly relative to whatever is present). `matchedGeometryEffect` was evaluated and rejected as unnecessary heavier machinery for a same-container position swap (research: `.scratch`/ios-api-researcher, 2026-07-12).
2. **Value cards**: weight (kg) and reps side by side. The focused card gets a dark-green background (`surfaceCardActive`), 1 pt bright-green border and soft glow; the inactive card is dark gray with a subtle border. Tapping a card moves focus (which the steppers act on).
3. **Fused action row**: `[<] [✓ + fill + segments] [>]` (icon-only capsule).
4. **Elapsed time & rest timer** (routine-row trailing slot, moved out of the toolbar 2026-07-24): the elapsed-time label — a stopwatch glyph + **large** bold tabular-monospaced digits (`elapsedFontSize` 16/15/13.5, `elapsedIconSize` 12/11.5/10, no capsule, `Color(white: 0.9)`) — sits right of the `Exercise X / Y` label. It's deliberately big and **grows upward into the free status-bar space** (design `.elapsed { margin-top: -14/-13/-11px }` + `.routine-top { align-items: flex-end }`). Implemented as a **baseline-pinned overlay**: the routine row is just the small label + a `Spacer` (`HStack(alignment: .firstTextBaseline)`), and the accessory is attached with `.overlay(alignment: .trailingFirstTextBaseline)`. `overlay(alignment:)` is contractually size-decoupling ("the original view continues to provide the layout characteristics"), so the accessory contributes **zero height** to the row and its extra height overflows upward, while `.trailingFirstTextBaseline` locks the time's text baseline to the label's. The stopwatch glyph is baselined against the digits with `.alignmentGuide(.firstTextBaseline) { $0[.bottom] - 0.1 * $0.height }` (Apple's documented SF-Symbol-vs-`Text` pattern). Requires no ancestor to apply `.clipped()`/`.mask()` above the row (verified — the content chain doesn't).

**Dead end (rejected 2026-07-24):** the first cut used a negative `.padding(.top, -N)` on the elapsed label with per-case magic constants (`elapsedTopOverlap` 7/6.5/5.5). An `ios-api-researcher` pass confirmed that *works* (the position math is sound — negative padding shrinks the reported frame without moving the content, so the baseline stays put) but is **fragile**: negative-inset semantics are undocumented, and the constant only cancels the height difference at the exact font size it was tuned for — it silently drifts (row grows, or content clips) under Dynamic Type or any font/icon change, with no compiler or runtime signal. The overlay approach needs no such constant and is robust to font-size changes, so `elapsedTopOverlap` was removed. While resting, the minimized rest countdown takes the same slot instead (mutually exclusive, as it was in the shared toolbar slot). The rest-timer **pill** overrides its baseline guide to its **bottom edge** (`.alignmentGuide(.firstTextBaseline) { $0[.bottom] }`) rather than its digits' baseline — its chrome extends below the text baseline, so baseline-pinning it like the plain elapsed text crowded the segment progress bar; bottom-pinning lifts the whole pill above the label line to clear the bar. Moved here because in the top toolbar the elapsed chip collided with the system clock (design note: *"vom Statusbar … in die Routine-Zeile verschoben"*). The toolbar's top-trailing slot is now empty (its `.toolbar {}` block was removed).

Vertical distribution (deviation from the strictly bottom-anchored mockup, user request 2026-07-12): the action row stays pinned at the bottom, while the editing group (rows 1–2) floats centered in the remaining space via flexible spacers — on large cases (Ultra) the surplus splits evenly above the steppers and between the cards and the action row instead of piling up under the toolbar; on 41 mm the spacers collapse to the compact design spacing, and on 40 mm to the halved `xSmall` floors (`editorTopGap` 2 / `editorBottomGap` 4) — those floors have to be small enough that the column fits at all, because a `Spacer(minLength:)` the layout cannot honour pushes the footer off the bottom edge rather than compressing.

## The Glass Complete Button
- **Capsule**: `.ultraThinMaterial` + radial green tint brightest above the top edge, 1 pt green border (35 % opacity), white light-edge gradient along the top, soft green glow shadow.
- **Progress fill**: a vertical-gradient green bar whose width is `completedSets/totalSets`, with a 1.5 pt bright trailing edge; animates with `spring(response: 0.35, dampingFraction: 0.8)` when a set completes.
- **Mini segments**: one 2.5 pt-high capsule per set under the glyph — bright green when completed; pending segments are translucent white, with the currently displayed set slightly brighter (deliberate deviation from the mockup, which had no position indicator, because the chevrons navigate sets here). Segments recolor with an 80 ms delay after the fill starts. Hidden for single-set exercises.
- **Glyph (icon-only, 2026-07-24)**: a single large checkmark (`completeIconSize` 17/15.5/13.5), tinted `completeCheckmark` #8DFFBB and bouncing on each completion. When the displayed set is already completed it switches to an undo arrow (kept toggle behavior — user decision, the mockup had no undo state). The **text label was removed** — the design made this an icon-only primary CTA (HIG: an unambiguous primary action lets the glyph replace the word; the fill + mini-segments carry the progress context). **`isFinishing` no longer changes anything visible** (the old "Finish Workout" text is gone; the state still drives the VoiceOver label and the auto-finish flow via `WatchWorkoutViewModel.isFinishingSet` — see `docs/watch-auto-finish.md`). On the done flash the glyph flips to dark `textOnDone` on the full-green capsule.
- **Done flash**: completing the last open set of an exercise flashes the capsule fully green (`doneGradient`, 160°-style diagonal) with dark "Done" text for ~800 ms while the ViewModel auto-advances to the next exercise underneath.
- **Press state**: scale 0.94 with `spring(response: 0.25, dampingFraction: 0.7)` (`PressScaleStyle`).
- All progress/pulse animations are disabled under Reduce Motion (plain crossfades remain).

## Auto-finish on the final set
Completing the **last remaining incomplete set anywhere in the routine** (any exercise, any order — order-independent, detected in `WatchWorkoutViewModel.applyToggleSetCompletion` when `findNextIncompleteSet()` returns nil) finishes the workout automatically instead of starting a rest timer / advancing: the "Done" flash plays, then the workout ends and `WatchWorkoutSummaryView` appears. Because the trigger lives in the shared completion path, the on-screen Complete button, the Ultra Action Button, and Double Tap all finish identically. Workouts with modified sets first route through the existing "Update your routine template?" prompt (via `requestsFinishConfirmation` → `ActiveWorkoutView`'s `showEndConfirmation` dialog). Full details in `docs/watch-auto-finish.md`.

## Chevron Buttons
Round dark buttons (`ChevronCircleStyle`): pressed state uses the lighter `strokeSubtle` background + scale 0.92; disabled (boundary) chevrons dim. They navigate **sets within the current exercise** — a deliberate deviation from the mockup's annotation (previous/next *exercise*), confirmed by the user 2026-07-12, since completing a set already auto-advances and exercise switching lives in the exercise list. The visual circle is 21–27 pt; the tap area is the full footer row height (`actionRowHeight`, 34–44 pt by case — see "Sizing per Case").

## Bottom Anchoring
The action row sits **within the bottom safe area** — it gets no extra bottom padding; the `actionRowHeight` tap frame is taller than the capsule it wraps, so it naturally leaves the capsule ~3–4.5 pt and the chevrons ~6.5–8.5 pt above the safe-area boundary (the smaller figure on `xSmall`). The design handoff was updated (2026-07-23) to formalize this: the mockup now draws per-case safe-area insets (`--sa-top/--sa-x/--sa-bottom`, with a deliberately larger bottom inset for the rounded corners) and a dashed "Safe Area" guide, requiring all interactive elements (chevrons, Complete button, elapsed chip) to stay inside the rounded safe-area rectangle. **watchOS supplies these insets automatically** — the app satisfies the design by not overriding the system safe area (only the background `.ignoresSafeArea()`), so the mockup's pixel inset values are *not* hardcoded (doing so would double-count against the system's). The 2026-07-24 handoff added one app-level inset on top: `--pad-chrome`, extra *horizontal* padding on the footer (fused) row (`CompactActionBar.fusedRowHPad` 14/15.5/13) so the round chevrons — which sit near the bottom corners where the curve bites in horizontally — stay inside the display curve. The system toolbar (now just the leading close button, since the elapsed chip moved into the routine row 2026-07-24) is positioned by watchOS, so its `--pad-chrome` needs no app code.

**Root cause / dead end (fixed 2026-07-23):** an earlier version deliberately pushed the row *below* the safe area via `FullScreenSetEditorView.bottomSafeAreaOverlap` (negative bottom padding = `safeAreaInset + touchFramePadding − footerBottomGap`) so the center capsule's visual bottom sat `footerBottomGap` (19/17/15 pt) above the *flat* mockup edge. On real hardware this **clipped the side chevrons**: the capsule is horizontally centered and clears the curved corners, but the left/right chevrons at that depth fall into the rounded-corner clip region and get sliced off (visible on the Ultra). The mockup is a flat rectangle, so it couldn't reveal this. Fix: respect the safe area (removed `bottomSafeAreaOverlap` and the now-orphaned `footerBottomGap` metric). Shrinking the Complete capsule horizontally to pull the chevrons inward was considered and rejected — it trades away the primary CTA's size and needs a per-case magic inset, whereas the safe area is the guaranteed-unclipped region at every watch size. Trade-off accepted: the capsule no longer hugs the very bottom edge as tightly as the mockup, and the whole editing stack rides a touch higher.

## Sizing per Case (`WorkoutScreenMetrics`)

**Four tiers** — `large` / `mid` / `small` / `xSmall` — defined in `Views/WorkoutScreenStyle.swift` together with the shared button styles. The first three are the handoff's 49 / 45 / 41 mm columns verbatim; `xSmall` is an app-side extrapolation below the design (see "The 40 mm overflow" below).

The tier is picked from `WKInterfaceDevice.current().screenBounds.size` by ranking **both axes independently and taking the tighter one** (`min(widthTier, heightTier)`):

| axis | large | mid | small | xSmall |
|---|---|---|---|---|
| width ≥ | 204 | 192 | 170 | — |
| height ≥ | 246 | 230 | 205 | — |

| case | logical pt | tier |
|---|---|---|
| 38 mm | 136 × 170 | xSmall |
| 40 mm (SE 1/2/3, S4–S6) | 162 × 197 | xSmall |
| 41 mm (S7–S9) | 176 × 215 | small |
| 42 mm (S10/S11) | 187 × 223 | small |
| 44 mm (SE 1/2/3, S4–S6) | 184 × 224 | small |
| 45 mm (S7–S9) | 198 × 242 | mid |
| 46 mm (S10/S11) | 208 × 248 | large |
| 49 mm Ultra 1/2 · Ultra 3 | 205 × 251 · 211 × 256 | large |

Two-axis ranking matters because the two axes disagree on real hardware: 44 mm is as *narrow* as 41 mm but as *tall* as 45 mm, and the failure mode of this screen is vertical overflow, so a width-only key measures the wrong thing (this is what the pre-2026-08-11 code did).

The tier governs: `completeButtonHeight` (35/33/30/28), `actionRowHeight` (44/44/44/34), `completeIconSize` (17/15.5/13.5/12.5), chevron ⌀ (27/26/23/21), `fusedRowHPad` (14/15.5/13/10 — extra horizontal inset on the footer row so the chevrons clear the curved corners, design `--pad-chrome`), stepper ⌀ (32/31.5/29/26), card height (40/40/35/31) and `valueCardGap` (6.5/6.5/6.5/5), the top-zone sizes `topNameSize` (15/14/12/11), `topPercentSize` (11/10.5/9.5/9), `topSegmentHeight` (3.5/3.5/3/2.5) and `topZoneSpacing` (6/5.5/4.5/3.5; the routine label↔bar gap is `topZoneSpacing − 2`, the routine↔exercise gap is `topZoneSpacing`), the editor's three gap floors `editorTopGap` / `clusterBottomGap` / `editorBottomGap` (4·7·8 on all tiers, 2·4·4 on xSmall), the compact HR/kCal readout (`metricValueSize` 14/14/14/12, `metricUnitSize` 11/11/11/9, `metricIconSize` 10/10/10/8, `metricRowSpacing` 5/5/5/2), and the large rest timer (see `watch-rest-timer-ui.md`). Stepper and card sizes were reduced 2026-07-24 (steppers 36/34/31→32/31.5/29, cards 46/43/37→40/40/35) to match the design update. The name/counter sizes are nudged ~2 pt above the handoff's strict 2× values (13/10.5 at 49 mm) for glanceable legibility during a workout.

### The 40 mm overflow (root cause, fixed 2026-08-11)

On an Apple Watch SE 3 40 mm the footer row was laid out **below the bottom edge** — the Complete capsule was sliced in half — while the same build was pixel-correct on an Ultra. Three compounding causes:

1. **The design's smallest column is not the smallest watch.** "Watch Final Design.html" draws 49 / 45 / 41 mm. A 40 mm screen is 162 × 197 pt: 14 pt narrower *and 18 pt shorter* than the 41 mm frame the `small` column was drawn on. The old table had no tier below it, so the 41 mm design was rendered on a screen that does not have room for it. `xSmall` is the missing fourth column, extrapolated by roughly the 197/215 height ratio.
2. **The tier was keyed on width alone** (`≥204 → large`, `≥192 → mid`, else `small`), so a vertical-overflow bug was being governed by a horizontal signal. Now `min(widthTier, heightTier)`.
3. **The footer row's height was a flat 44 pt on every case**, because both `CompactActionBar.completionButton` and `ChevronCircleStyle` framed themselves to `OnyxWatch.Dimensions.minTouchTarget`. The tier's `completeButtonHeight` only shrank the *visible* capsule; the row kept its iOS-sized 44 pt block — 22 % of a 197 pt display. That constant is now the tiered `actionRowHeight`, and `ChevronCircleStyle` takes it as an init parameter. Handoff §6 sets the watchOS floor at 24 pt ("Mindest-Hit-Targets ≥ 24 pt"), so 34 pt on `xSmall` still clears it with slop around the 28 pt capsule. **`ChevronCircleStyle` also carries an explicit `minWidth: 24`** — `.frame(height: rowHeight)` constrains only the vertical axis, so without it the chevron's tap rect would be exactly the 21 pt visual circle on `xSmall`, i.e. below the floor on the horizontal axis while the doc claimed it cleared it.

Contributing: the two `Spacer(minLength:)` floors in `FullScreenSetEditorView` (4 pt and 8 pt) are floors the layout **cannot go below**, so once the column exceeded the container the surplus was dumped past the bottom edge instead of being absorbed. They are `editorTopGap` / `editorBottomGap` now, halved on `xSmall`. And `WorkoutMetricsView(size: .small)` — the tallest element of the editor's middle band at ~39 pt — had fixed sizes on every case; it now follows the tier (~31 pt on `xSmall`).

Regression guard: `GymStreakWatchUITests.testControlsStayOnScreenOnSmallestCase` asserts the Complete button and the rest timer's Skip button are fully inside `app.frame`. Run it against `Apple Watch SE 3 (40mm)` — on a larger case it passes trivially. Verified 2026-08-11 on the 40 mm simulator in de-DE (the worst case for label lengths).

## Colors
Workout-screen tokens live in `OnyxWatch.Colors` (`OnyxWatchDesignSystem.swift`): `accentGreen` #34E07A (fill, border, glow), `completeCheckmark` #8DFFBB (the icon-only Complete glyph, brighter than accent), `surfaceCardActive` #0C2417, `stepperGreen` #1D5138 / `stepperIcon` #63EF9B, `strokeSubtle` #3A3A3C, `textMuted` #98989D, `segmentFill` #5C5C60, `chipBackground` #1A1A1C / `chipText` #C7C7CC, `glassLabel` #EAFFF2 (legacy — no longer used since the button went icon-only), `doneGradient` #6DFFA8→#2FD873→#17B45A with `textOnDone` #03140A. Background stays pure black (AMOLED).

## Haptics & Interaction
- Complete: `.success`; Undo: `.directionDown` — played once, by `WatchWorkoutViewModel.applyToggleSetCompletion`, so the exercise list and the Action Button intent get the same feedback (the action bar used to play a duplicate copy; consolidated 2026-07-12). Set navigation `.click` is played by `FullScreenSetEditorView.goToPreviousSet/goToNextSet`.
- The handoff specifies `.notification` for the exercise-done moment; deliberately omitted because the ViewModel already plays `.success` for the completing tap and stacking both felt muddy.
- The complete button carries `.handGestureShortcut(.primaryAction)`, so Double Tap (Series 9/10, Ultra 2/3) triggers it; on Ultra models the Action Button completes the current set via App Intents — see [action-button.md](./action-button.md).

## Accessibility
- Complete button: "Complete/Undo set X of Y"; decorative segments hidden from VoiceOver.
- Chevrons: "Previous/Next set" with "Set X of Y" value.
- Steppers: "Increase/Decrease" with the focused field ("Weight"/"Reps") as value.
- Value cards: combined label "WEIGHT. 80 kg" etc., `isSelected` trait on the focused card.
- **Dynamic Type — deliberately fixed-size (non-scaling).** Every font on this workout HUD is built from a fixed `.font(.system(size:))` (the `WorkoutScreenMetrics` values, and `RestTimerMinimizedPill`'s internal 13 pt countdown / 10 pt chevron), so the whole screen is intentionally inert to the user's text-size setting. This is a deliberate trade-off for a space-critical, glanceable-during-exercise HUD: nothing reflows or clips at large accessibility text sizes, and the routine-row baseline-overlay math (which lets the elapsed time / rest-timer pill overflow upward with zero row-height contribution) stays stable. The rest-timer pill's fixed 13 pt digits are what keep it within its `.frame(maxHeight: 22)` cap. If scalable fonts are ever adopted here, pair any hard `dynamicTypeSize` ceiling with `.accessibilityShowsLargeContentViewer()` (Apple's recommendation). Verified best-practice via `ios-api-researcher` 2026-07-24.

## Scrolling exercise name (`WatchMarqueeText`, 2026-09-01)

**Problem.** The exercise name shares its row with the `Set X/Y` counter, so it gets
roughly half the screen width — about 16–18 characters at `topNameSize`. German
exercise names routinely blow past that: measured against the shipped German seed
catalog (`GymStreak/Resources/de.lproj/Localizable.strings`, keys `seed.exercise.*`),
**47 of 96 names overflow**, and the longest — `Kreuzheben mit gestreckten Beinen`
(33 chars) — wants roughly 230 pt in a ~130 pt slot.

**Why no static layout fixes it.** Three things were measured and rejected:

- **Shrinking further.** At 33 characters, even `minimumScaleFactor(0.7)` cannot fit
  the name on a 184–208 pt screen at a size that is legible mid-set. Static scaling
  provably runs out before the longest names fit.
- **Dropping the parenthetical qualifier first** (give `Kniebeuge` higher layout
  priority than `(Langhantel)`). This was actively harmful and is the key finding:
  **ten seed name groups differ ONLY in their trailing qualifier** — `Bankdrücken`
  ×3 (Langhantel/Kurzhantel/Multipresse), `Bizeps-Curls` ×3, `Kniebeuge`
  ×2 (Langhantel/Multipresse), `Schrägbankdrücken` ×2, `Schulterdrücken`,
  `Schulterheben`, `Seitheben`, `Klimmzug`, `Crunches`, `Ausfallschritte`. Truncating
  or dropping the tail renders genuinely different exercises **identically**. Only
  32% of names even have a parenthetical, so it also covers a minority of the problem.
  It takes 20 characters of prefix before no two seed names collide.
- **Wrapping to two lines.** Costs vertical space on a screen that is already tight
  on the `xSmall` (40 mm) tier, and the user's constraint was explicitly to leave the
  layout dimensions alone.

**Mechanism.** There is **no built-in marquee on watchOS** — verified via
`ios-api-researcher` against Apple's docs: no SwiftUI modifier scrolls overflowing
`Text`; `.truncationMode`, `.allowsTightening` and `.lineLimit(_:reservesSpace:)` are
all static; `ViewThatFits` picks a variant once; the Now Playing marquee is private
system chrome with no public equivalent; and `WKInterfaceLabel` is both static and
unreachable from a SwiftUI-lifecycle watch app. `TextRenderer`/`Text.Layout`
(watchOS 11+) *is* available and could draw a marquee, but it is a drawing
customizer, not a clipping/scrolling container — it would be strictly more machinery
for the same result. So `WatchMarqueeText` is hand-built from ordinary layout.

**How it is built** (`GymStreakWatch Watch App/Views/WatchMarqueeText.swift`):

- A **clear copy of the text owns the layout**. It compresses exactly like a normal
  truncating `Text`, so it hands the row its width, height *and first text baseline*.
  This is why it is not a `GeometryReader`: a `GeometryReader` has no text baseline
  and would break the name/`Set X/Y` `.firstTextBaseline` alignment the row depends on.
- A **hidden `.fixedSize()` probe** in a `.background` measures the width the text
  *wants*; `.onGeometryChange` on the layout owner measures the slot. Overflow is the
  difference. `.onGeometryChange` is used rather than `GeometryReader` +
  `PreferenceKey` because the preference callback is `@Sendable` and cannot touch
  `@State` under the watch target's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- The **visible label** switches on one flag: `.fixedSize(horizontal: isAnimating)`.
  On, it renders at natural width, is clipped by the parent, and `offset(x:)` slides
  it. Off, it is proposed the slot width and truncates with a normal ellipsis —
  byte-identical to the pre-marquee label.

**Scroll threshold — it is not a magic number.** The label only moves when overflow
exceeds what `minimumScaleFactor(0.85)` could still absorb. A label of natural width
`W` in slot `S` fits at scale `f` when `W · f ≤ S`; with `f ≥ 0.85` that holds exactly
while `W − S ≤ S · (1/0.85 − 1)`. Below that it just shrinks, as before — nothing
slides for three points of overflow.

**Cycle pacing — deliberately head-dominant.** `headDwell` 2.2 s → travel at
32 pt/s → `tailDwell` 1.4 s → eased 0.45 s return, repeating. The resting head state
is the single longest phase on purpose: a 1–2 second mid-set glance lands on the same
familiar prefix the static label always showed, which is what makes continuous motion
acceptable on a glance screen. Sequenced with `Task.sleep` inside `.task(id:)` rather
than a `repeatForever` animation, because a single repeating animation cannot hold
still at the ends, and the dwells are the whole point.

**Gating.** Motion is suppressed and the label parks at the head when either
`accessibilityReduceMotion` or `isLuminanceReduced` (wrist-down / Always-On) is set —
in AOD the system throttles refresh to ~1 Hz, so an animation would neither read well
nor be honoured, and parking guarantees a dimmed glance never catches a frozen middle
substring. The reset runs inside a `Transaction` with `disablesAnimations = true`, so
a cancelled cycle's in-flight linear animation cannot keep sliding the label after
motion was switched off. `.task(id: cycleIdentity)` keys on text + animating-state,
so the cycle restarts on exercise change and tears down immediately when motion
becomes unwanted. It deliberately excludes the overflow — see the task-thrash defect
below. The tradeoff: if the slot width changes mid-pass (the counter widening `1/9` →
`1/12`), that pass still travels the previous overflow and self-corrects on the next
one, since `runCycle()` re-reads the geometry each pass.

**Two defects the architecture review caught (2026-09-01), both now fixed** — worth
recording because neither is visible in a build or in the unit suite:

- **Stale offset across an exercise change.** `offset` is `@State` on a view instance
  that *survives* the exercise changing: `FullScreenSetEditorView` swaps the name
  through a computed `displayedExercise` rather than re-pushing the screen, so
  nothing resets it. `runCycle()` originally opened with its head dwell, which meant
  the NEW name was drawn at the OLD name's scroll offset — almost entirely off its
  own head — for a full 2.2 s, then animated backwards when the new name was
  shorter. Fires on most long-name → long-name transitions, i.e. exactly the German
  case the feature exists for. Fix: `settleAtHead()` runs unconditionally as the
  first statement of `runCycle()`, before the `isAnimating` guard.
- **Task thrash from animated geometry in the task id.** `cycleIdentity` embedded the
  rounded overflow. An ancestor animates on `currentExerciseIndex`/`currentSetIndex`,
  so the slot width *interpolates* (e.g. as the counter goes `1/3` → `1/12`) and
  `onGeometryChange` reports every intermediate frame — cancelling and recreating the
  task a dozen times per transition. The dependency was also unnecessary, since
  `runCycle()` re-reads `cycle` on each pass. Fix: the id is `text | isAnimating`.

**Accessibility.** Unchanged and unaffected: `WorkoutTopProgressView` already builds
its combined accessibility label from the full, untruncated `exerciseName`, so
VoiceOver never depended on the visual truncation. The measurement probe is
`accessibilityHidden(true)`.

**Two invariants added 2026-09-01**, when the rest timer became the second call
site (`docs/watch-rest-timer-ui.md` § "Naming the exercise when it changes"):

- The hidden **layout owner is pinned to `minimumScaleFactor(1)`**. An ancestor's
  scale factor reaches the owner but not the visible label (which sets its own
  0.85 floor and goes `fixedSize` at full scale while scrolling), so without the
  pin the base box can be *shorter* than the label — and `.clipped()` clips to
  the base, shaving a scrolling name's ascenders. Harmless where no ancestor
  scales (the top zone), load-bearing where one does (the rest caption's 0.6).
- **`isSuspended`** stops the cycle while the label is mounted but unreadable
  (behind `opacity(0)`, collapsed, or occluded). It folds into `isAnimating` and
  therefore into `cycleIdentity`, so it toggles the `.task` rather than the
  view's existence: `@State` survives, the label parks at the head, and lifting
  the suspension restarts the head dwell — which is what a reader wants at the
  moment the label becomes visible. Gating with an `if` at the call site instead
  would destroy the `@State` and recreate the task on every toggle.

**Suspended under the full-screen rest timer (2026-09-02).** The top zone's own
marquee is suspended while the large rest timer covers it. This is not optional
tidiness: `WorkoutRestTimerOverlay` is a *sibling* of `ActiveWorkoutView`'s
`NavigationStack`, so a pushed `FullScreenSetEditorView` is **never unmounted**
when a rest starts — it is merely painted over by an opaque, screen-filling
surface, and occlusion is not visibility as far as SwiftUI is concerned. Without
a signal the name measured, scrolled and re-animated with its `Task` alive for
the entire rest, behind a surface nobody can see through; and since completing a
set *here* is how a rest normally starts, every rest paid it whenever the name
overflows.

The signal is the environment value **`\.isCoveredByRestTimer`** — declared
beside `\.isRestPillStepperOpen` in `WorkoutRestTimerOverlay.swift`, published by
`ActiveWorkoutView` as `viewModel.isResting && !viewModel.isRestTimerMinimized`,
read by `WorkoutTopProgressView` and handed straight to `isSuspended`. Note the
`!isRestTimerMinimized` half: a *minimized* rest leaves the editor genuinely
visible, so suspending there would be a regression, not a saving. An environment
key rather than an `@EnvironmentObject` because this view is a pure layout
container and observing the view model would re-render it on every countdown
tick; and rather than a threaded parameter because the key beside it already
proves the route reaches a `NavigationStack` destination. Reduce Motion and
Always-On are unaffected — all three conditions park the label at its head, so
they compose instead of fighting. Full reasoning in
`docs/watch-rest-timer-ui.md` § "The covered screen stops working".

**Tests.** `GymStreakWatchTests/WatchMarqueeTextTests.swift` — 9 cases pinning the
shrink/scroll handover at the scale floor, the zero-width first-layout guard, travel
timing, and the head-dominance invariant.

## Why the exercise LIST does not scroll its names (2026-09-02)

The exercise list (tab 0 of the active workout) has the same overflow problem and a
**different answer**: the name gets the full row width and wraps to a second line,
rather than becoming a marquee.

**The problem was worse here than in the top zone.** On 40 mm the row read
"Kniebe…" / "Bankdr…" — roughly six characters — which is precisely the failure the
marquee exists to prevent, and it lands on the screen where the user *picks* between
`Bankdrücken (Langhantel)`, `(Kurzhantel)` and `(Multipresse)`. All four long names in
the shipped starter routine are 22–26 characters.

**Half of it was a layout bug, not a space shortage.** Measured on 40 mm against device
screenshots: the name occupied a **45.5 pt** slot while **~51 pt of the row sat empty**
between it and the chevron. `Text` and the trailing `Spacer(minLength: 4)` are both
flexible, so the `HStack` split the surplus between them. Replacing the `Spacer` with
`.frame(maxWidth: .infinity, alignment: .leading)` on the text column — the same
substitution `CompactActionBar` makes — widened that slot to **~77 pt**, the name's
trailing edge reaching x=122 pt against a chevron starting at x=137.5 pt (the 45.5 pt
and ~77 pt figures are widths; 122 and 137.5 are x-coordinates on the 162 pt screen). A `.layoutPriority(1)` on the column while keeping the `Spacer` was tried
first and only reached 60.5 pt: a **wrapped `Text` negotiates its own ideal width**
instead of consuming the whole proposal, so the explicit frame is what is load-bearing.

**Then two lines, not a marquee.** `lineLimit(2)` + `minimumScaleFactor(0.8)` renders
`Kniebeuge (Langhantel)` in full (verified on the 40 mm simulator). Three reasons the
marquee was rejected here even though it is the right answer one screen over:

- **`WatchMarqueeText` must never go in a `List`/`ForEach` row.** Each instance costs
  three text measurements, a long-lived `Task` and a repeating animation; per row that
  is exactly the per-item cost the rendering rules prohibit. A six-exercise routine
  would mount six of them, and rows scroll off-screen while still animating — the same
  fault as `docs/watch-rest-timer-ui.md` § "The covered screen stops working", multiplied.
- **Six names sliding at once is noise.** The top zone works *because* there is exactly
  one moving label on the screen.
- **Vertical growth is affordable in a scrolling list.** Wrapping was rejected for the
  set editor because that screen is fixed-height and already tight at 40 mm; a `List`
  simply scrolls. This is the whole reason the same problem gets opposite answers, and
  it is why the two-line row is not an inconsistency.

A row with a long name grows from the 44 pt `minTouchTarget` floor to roughly 55 pt, so
slightly fewer rows are visible at once. Accepted: a legible name beats a denser list of
ambiguous ones.

**What still clips, and why that was accepted.** Two lines at the 0.8 scale floor hold
roughly 25 characters (the slot is ~77 pt; `(Langhantel)` rendered 12 characters in
74 pt, i.e. already at the floor). **20 of the 96 German seed names exceed that** — the
longest being `Trizepsdrücken über Kopf (Kurzhantel)` (37), `Schulterdrücken sitzend
(Kurzhantel)` (36) and `Kreuzheben mit gestreckten Beinen` (33) — so their tail still
truncates on the second line. That is accepted because the *qualifier* becomes partially
visible even then (`Schulterdrücken (Langhante…` vs `(Maschine)`), which is what
disambiguation actually requires; the failure being fixed was a name cut to six
characters, not the last two glyphs of a long one. Thirteen names also contain a single
word over 14 characters (`Konzentrationscurls`, `Negativbankdrücken`, …) which cannot
wrap at all and can only shrink.

**The swappable row is narrower and was NOT measured.** Every figure above is from the
**chevron** row (`!isComplete && !canSwap`). A row with `canSwap == true`
(`completedSetsCount == 0 && !alternatives.isEmpty`) hides the ~7 pt chevron but hands a
44 pt button plus 4 pt of spacing to a sibling of the text column, so its name slot is
roughly **60–66 pt rather than 77 pt** — about 10–11 characters per line, i.e. ~20–22
over two lines at the 0.8 floor. `Kniebeuge (Langhantel)` (22) is borderline there and
`Bankdrücken (Langhantel)` (24) still clips. This is derived from the layout, **not
measured**: the state was not reachable on the verification simulator, whose synced data
carries no alternatives, so no row in it had `canSwap == true`. It matters more than the
number suggests, because per `docs/alternative-exercises.md` a row offers a swap
precisely when equipment variants exist — exactly the names whose trailing qualifier is
the disambiguator. Reclaiming width there means shrinking the swap button's outer
`.frame(width: 44, height: 44)`, which is a touch-target decision and was deliberately
left alone.

Two knobs remain if full names are ever wanted, in increasing cost: `lineLimit(3)`
covers the whole catalog (37 characters) at the price of ~74 pt rows for that 21%, or
dropping the trailing chevron frees ~24 pt of width (≈3 characters per line) for no
vertical cost, at the price of the affordance that signals the row pushes a detail
screen. Lowering the scale floor below 0.8 was rejected — `docs/watch-set-completion-button.md`
already argues 0.7 is the edge of mid-workout legibility, and even 0.6 does not fit the
longest names in two lines.

## Architecture
### Components Involved (all watchOS target)
- **`CompactActionBar.swift`**: fused action row (glass complete button + chevrons)
- **`WorkoutTopProgressView.swift`**: top zone — routine level (`Exercise X / Y` label + neutral-gray per-exercise segment bar) and exercise level (name + green-accented `Set X/Y` counter); a **pure layout container** — it holds no state and never reaches for the view model, taking its data as init params (`exerciseName`, `exerciseIndex`/`exerciseCount`, `setIndex`/`setCount`, `exerciseProgress`), its trailing accessory as a `@ViewBuilder`, and the two rest-timer signals it must react to from the environment (`\.isRestPillStepperOpen` fades the routine label under the grown pill; `\.isCoveredByRestTimer` suspends the name's marquee under the large timer)
- **`WatchMarqueeText.swift`**: the single-line label that scrolls its overflow through a fixed slot instead of ellipsizing it, plus `WatchMarqueeCycle` (pure scroll-threshold + pacing geometry, unit-tested). Used for the exercise name in the top zone, and — since 2026-09-01 — for the exercise name on the full-screen rest timer's caption line, where the slot is far narrower (58 pt at 40 mm) and the same tail-truncation argument applies with more force (`docs/watch-rest-timer-ui.md` § "Naming the exercise when it changes"). **Single-instance only — never in a `List`/`ForEach` row**: each instance costs three text measurements, a long-lived `Task` and a repeating animation, which per row is exactly the per-item cost the rendering rules prohibit
- **`FullScreenSetEditorView.swift`**: screen layout, shared steppers, done-flash state, rest/elapsed toolbar status; passes the current exercise/set indices and counts, and derives `exerciseProgress` (per-exercise completion fractions) from `viewModel.exercises`, into the top zone
- **`CompactValueEditor.swift`**: weight/reps value card (steppers were moved out of it into the editor)
- **`WorkoutScreenStyle.swift`**: `WorkoutScreenMetrics` size tiers, `PressScaleStyle`, `ChevronCircleStyle`
- **`OnyxWatchDesignSystem.swift`**: workout-screen color tokens
- **`ExerciseListView.swift`**: owns the alternative-picker sheet and visible/swipe Swap actions on eligible exercise rows; its row gives the exercise name the row's full width and up to two lines (see "Why the exercise LIST does not scroll its names"); also defines `WorkoutMetricsView` reused for the BPM/kCal column

### How It Works
- `CompactActionBar` receives `isCompleted`, `currentSetIndex`, `totalSets`, `completedSets`, and `showDoneFlash` as parameters; it holds no state of its own.
- Previous/Next only change the displayed set; they never alter completion state.
- The done flash is detected in `FullScreenSetEditorView.toggleSetCompletion()` (the tap completes the exercise's last open set) *before* calling the ViewModel, because the ViewModel immediately auto-advances `currentExerciseIndex`/`currentSetIndex` afterwards; the flash is a local `@State` cleared after 800 ms.
- Single-set exercises show only the capsule (no chevrons, no segments).
- Elapsed time comes from the existing `viewModel.elapsedTimeString` publisher (the handoff suggests `TimelineView`; the existing per-second publisher was kept — no new plumbing). Since 2026-07-24 it renders in the routine row (see item 4 above), so the old `.offset(y: -8)` clock-centerline alignment hack — needed only while it was a toolbar trailing item — is gone.
- The editor is pushed onto the shared `NavigationStack` owned by `ActiveWorkoutView` (`navigationDestination(for: Int.self)` keyed by exercise index); it has no stack of its own and uses the native back button.

## Design Exploration & History
- An earlier iteration (still visible in git history) used a two-tier dock: a segmented navigation rail above a dark "Complete"/"Undo" capsule. It solved the "Next ≠ Complete" confusion but spent vertical space on a separate progress row. The final design fuses progress *into* the button (fill + mini segments) and returns the chevrons to a single row.
- Before that, numeric badges and literal progress dots were rejected (no per-set completion info / cramped at high set counts).
- The button carried a verb text label ("Complete"/"Undo"/"Finish Workout") from the first single-row design through 2026-07-23; the label originally guarded against the semantic trap where chevrons beside a status-labelled button read as if Next completed the set. The **2026-07-24 design update dropped the text for an icon-only checkmark** — with the chevrons now unambiguously navigation and the fill + mini-segments carrying progress, the primary CTA is clear enough that the glyph replaces the word (HIG). VoiceOver still reads the full verb ("Complete/Undo set X of Y"), so the semantics survive for non-visual use.
- **Deviations from the mockup** (all deliberate, decided 2026-07-12): chevrons navigate sets not exercises; the Undo toggle state is kept; the current set's pending segment is slightly brighter; no `.notification` haptic on the done flash.
- **Top-zone segment fill** generalizes the handoff (which fills only the *current* exercise's segment): every exercise's segment fills to its own completed/total ratio, so a partially-finished earlier exercise still shows its progress instead of reading as empty. Strictly more informative and needs no "which is current" input.

## Runtime Warning Fixes (2026-07-12)
The console warnings "Update ToolbarReader tried to update multiple times per frame" / "Update navigationEventHandlers tried to update multiple times per frame" are SwiftUI AttributeGraph diagnostics: an internal node feeding the `NavigationStack`'s toolbar/event machinery was invalidated more than once per display frame. Repeating continuously (as here, driven by per-second timers and HealthKit callbacks), they indicate a real feedback pattern, not benign noise. Four combined fixes:

1. **Coalesced HealthKit publishing**: `WatchHealthKitManager.workoutBuilder(_:didCollectDataOf:)` used to spawn one `Task { @MainActor }` per collected sample type — heart rate + energy arriving in the same callback landed as separate SwiftUI transactions in one frame. Now all collected types are applied in a single main-actor hop.
2. **Deduplicated view-model pipelines**: `WatchWorkoutViewModel` maps heart rate/calories to `Int` and the elapsed time to its formatted string *before* `removeDuplicates()`, so bursts of near-identical HealthKit samples no longer republish unchanged display values (each republish invalidated every observing view).
3. **Animations scoped to content**: the four `.animation(_:value:)` modifiers moved off the `NavigationStack` onto the content `VStack` — stack-level implicit animations bleed into toolbar/navigation internals (a known anti-pattern per Swift Forums threads on `NavigationAuthority`/preference warnings).
4. **No `.transition` in `ToolbarItem`**: the minimized rest timer's `.move+opacity` transition inside the toolbar builder was removed (transitions inside `ToolbarItem` builders are unsupported and fed the same warnings).
5. **Single shared `NavigationStack` wrapping the TabView** (fixed the remaining warning burst on exercise tap plus a `UIScrollView does not support multiple observers…` PUIC assert): tab 0 of `ActiveWorkoutView` used to swap `ExerciseListView` ↔ `FullScreenSetEditorView` manually in a `ZStack` with `withAnimation` + `.transition(.move)`, where the editor created its *own* `NavigationStack` mid-animation. A first fix (stack *inside* tab 0) still left two PUIC navigation controllers observing the carousel list. Final topology follows Apple's watch workout-app pattern: `NavigationStack(path:) { TabView(.verticalPage) }` with the editor pushed **over the tabs** via `navigationDestination(for: Int.self)` — one navigation controller per presentation context. Native slide + edge-swipe back replace the old custom `DragGesture`; the editor's custom toolbar back button was dropped for the native back chevron. **Behavior change:** while the set editor is open, vertical paging to Metrics/Controls is unavailable (go back to the list first) — matching Apple's own workout app.

Sources: Swift Forums "Preference tried to update multiple times (SwiftUI)" (t/47451), "Update NavigationAuthority bound path…" (t/66673), Apple Developer Forums thread 708592, TCA discussion #2514. See [action-button.md](./action-button.md) for the related simulator-only intent-donation error (`NSCocoaErrorDomain 4099`).

## watchOS UX/API Research
- **Workout status:** Apple recommends displaying elapsed or remaining time during active workouts, so a conditional action must not replace it — the routine-row trailing slot always shows rest countdown or elapsed time (moved there from the toolbar top-trailing slot 2026-07-24).
- **Swap placement:** The exercise list is the owning context for exercise identity and alternatives. A visible row accessory provides direct access; swipe remains a shortcut.
- **Dead ends:** An inline Swap pill broke the non-scrolling editor layout. Replacing elapsed time with Swap hid persistent status. `secondaryAction` is explicitly unavailable on watchOS. Context menus are unsupported on watchOS and were removed.
- **Compatibility:** Uses `ultraThinMaterial`, gradients, `symbolEffect(.bounce)`, and existing sheet/toolbar APIs within the current watchOS target. No entitlement, permission, persistence, or ViewModel change was required.
- **Sources:** [Apple Human Interface Guidelines — Workouts](https://developer.apple.com/design/human-interface-guidelines/workouts), [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons?changes=latest_1__8), [Gestures](https://developer.apple.com/design/human-interface-guidelines/gestures), [Context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus)
- **Detailed report:** [Watch Set Editor Control Placement Research](../.scratch/watch-set-progress-in-button/ux-control-placement-research.md)

### Targets
- **watchOS**: `GymStreakWatch Watch App` — this is watch-only UI
- **iOS**: Not affected — iOS workout UI uses different components
