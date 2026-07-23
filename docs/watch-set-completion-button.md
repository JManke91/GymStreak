# Watch Workout Screen — Set Completion & Action Dock

## Overview
The bottom of the watch workout screen (`FullScreenSetEditorView`) is a fused action row: two round set-navigation chevron buttons flanking a glass-style "Complete" capsule (`CompactActionBar`). The capsule's translucent green fill and mini segments show set progress (completed sets / total), while its label always stays an action verb ("Complete", or "Undo" when the displayed set is already completed). Above the row sit the weight/reps value cards with shared round +/− stepper buttons and live heart-rate/calorie metrics.

The visual design comes from a Claude Design handoff bundle: `design/gym-streak/project/Watch Final Design.html` with exact specs in `design/gym-streak/project/SwiftUI Handoff.md` (implemented 2026-07-12).

## Screen Layout (action row pinned, editing group centered)
0. **Top zone** (`WorkoutTopProgressView`, added 2026-07-12 from the Final design, handoff §4; **decoupled into two context levels 2026-07-23**): Fills the space between the toolbar (clock/elapsed chip) and the stepper cluster with two stacked levels so the routine-level and exercise-level context never blur together:
   - **Routine level** (top): an uppercase `Exercise X / Y` label (`textMuted`, kerned; localized key `Exercise %lld / %lld` → de `Übung %lld / %lld`) above the per-exercise segment bar — one segment per exercise in workout order, each a dark `segmentTrack` (#2A2A2C) capsule with a leading fill sized to that exercise's completed/total sets. The fill is **neutral gray `segmentFill` (#5C5C60), not green** — green is now reserved exclusively for the current set (its counter number and the Complete button fill), so the bar can never be misread as green "exercise progress".
   - **Exercise level** (below the bar): the current exercise name (bold, `lineLimit(1)` + `minimumScaleFactor(0.85)`) on the left and a `Set X/Y` counter on the right, where the current set number is `accentGreen` + bold and the `/total` is muted (`Text` concatenation; label from localized key `Set`).
   - The earlier design showed the exercise name on top with a whole-workout completion **percent** (removed) and a green segment bar; both the percent and the `workoutProgress` init param are gone.
1. **Steppers + metrics row**: two round dark-green +/− buttons adjust the focused value card; live ❤️ BPM and 🔥 kCal metrics (`WorkoutMetricsView`, shown only when HealthKit delivers values). The +/− cluster **follows focus** — it sits on the same side as the focused card (weight = left, reps = right) and slides to the other side, past the metrics column, when focus moves, so the steppers always read as directly controlling the focused card. Restored 2026-07-12 — the glass-button redesign (`0ce2bdd`) had pinned the steppers to the left, breaking this context link.
   - **Smooth swap implementation**: the row is a `ForEach(clusterOrder, id: \.self)` over a stable `ClusterSlot` identity (`.steppers`/`.metrics`), NOT an `if/else` reorder. Keying on the slot identity (never on position) lets SwiftUI treat the focus change as a *move* and interpolate each cluster's frame into a slide; an `if/else` swap only crossfades because its branches are distinct identities. Each slot uses an equal-width `frame(maxWidth: .infinity, alignment:)` (alignment derived from focus, not row position) to hug its outer edge — this stands in for the old `Spacer`, which jitters when placed between reordered `ForEach` items. Animated with `.snappy(duration: 0.22, extraBounce: 0.05)` on `value: clusterOrder`, guarded by `accessibilityReduceMotion` (no animation when reduce-motion is on). The metrics slot is dropped from `clusterOrder` entirely until HealthKit delivers values (it then fades in as an insert; the steppers still slide correctly relative to whatever is present). `matchedGeometryEffect` was evaluated and rejected as unnecessary heavier machinery for a same-container position swap (research: `.scratch`/ios-api-researcher, 2026-07-12).
2. **Value cards**: weight (kg) and reps side by side. The focused card gets a dark-green background (`surfaceCardActive`), 1 pt bright-green border and soft glow; the inactive card is dark gray with a subtle border. Tapping a card moves focus (which the steppers act on).
3. **Fused action row**: `[<] [✓ Complete + fill + segments] [>]`.
4. **Toolbar top-trailing**: minimized rest countdown while resting; otherwise a calm elapsed-time capsule chip (stopwatch glyph + tabular monospaced digits so it doesn't jitter while counting).

Vertical distribution (deviation from the strictly bottom-anchored mockup, user request 2026-07-12): the action row stays pinned at the bottom, while the editing group (rows 1–2) floats centered in the remaining space via flexible spacers — on large cases (Ultra) the surplus splits evenly above the steppers and between the cards and the action row instead of piling up under the toolbar; on 41 mm the spacers collapse to the compact design spacing.

## The Glass Complete Button
- **Capsule**: `.ultraThinMaterial` + radial green tint brightest above the top edge, 1 pt green border (35 % opacity), white light-edge gradient along the top, soft green glow shadow.
- **Progress fill**: a vertical-gradient green bar whose width is `completedSets/totalSets`, with a 1.5 pt bright trailing edge; animates with `spring(response: 0.35, dampingFraction: 0.8)` when a set completes.
- **Mini segments**: one 2.5 pt-high capsule per set under the label — bright green when completed; pending segments are translucent white, with the currently displayed set slightly brighter (deliberate deviation from the mockup, which had no position indicator, because the chevrons navigate sets here). Segments recolor with an 80 ms delay after the fill starts. Hidden for single-set exercises.
- **Label**: checkmark + "Complete" (bold); the checkmark bounces on each completion. When the displayed set is already completed the label switches to an undo arrow + "Undo" (kept toggle behavior — user decision, the mockup had no undo state). When the displayed set is the **last remaining incomplete set of the whole workout**, the label reads **"Finish Workout"** instead (driven by `WatchWorkoutViewModel.isFinishingSet`, passed in as `CompactActionBar.isFinishing`) — see `docs/watch-auto-finish.md`.
- **Done flash**: completing the last open set of an exercise flashes the capsule fully green (`doneGradient`, 160°-style diagonal) with dark "Done" text for ~800 ms while the ViewModel auto-advances to the next exercise underneath.
- **Press state**: scale 0.94 with `spring(response: 0.25, dampingFraction: 0.7)` (`PressScaleStyle`).
- All progress/pulse animations are disabled under Reduce Motion (plain crossfades remain).

## Auto-finish on the final set
Completing the **last remaining incomplete set anywhere in the routine** (any exercise, any order — order-independent, detected in `WatchWorkoutViewModel.applyToggleSetCompletion` when `findNextIncompleteSet()` returns nil) finishes the workout automatically instead of starting a rest timer / advancing: the "Done" flash plays, then the workout ends and `WatchWorkoutSummaryView` appears. Because the trigger lives in the shared completion path, the on-screen Complete button, the Ultra Action Button, and Double Tap all finish identically. Workouts with modified sets first route through the existing "Update your routine template?" prompt (via `requestsFinishConfirmation` → `ActiveWorkoutView`'s `showEndConfirmation` dialog). Full details in `docs/watch-auto-finish.md`.

## Chevron Buttons
Round dark buttons (`ChevronCircleStyle`): pressed state uses the lighter `strokeSubtle` background + scale 0.92; disabled (boundary) chevrons dim. They navigate **sets within the current exercise** — a deliberate deviation from the mockup's annotation (previous/next *exercise*), confirmed by the user 2026-07-12, since completing a set already auto-advances and exercise switching lives in the exercise list. The visual circle is 23–27 pt; the button keeps a 44 pt-tall tap area.

## Bottom Anchoring
The action row intentionally extends below the bottom safe-area boundary: `FullScreenSetEditorView.bottomSafeAreaOverlap` shifts it down by `safeAreaInset + touchFramePadding − footerBottomGap` so the capsule's visual bottom sits exactly `footerBottomGap` (19/17/15 pt) above the physical screen edge, matching the mockup's footer position. Relying on the safe-area boundary alone (an earlier version capped the overlap at 8 pt) left the row ~10–15 pt too high, especially on the Ultra's large bottom inset. The mockup demonstrates the row clears the curved corners at this height, and the 44 pt tap frames are unchanged.

## Sizing per Case (`WorkoutScreenMetrics`)
Three tiers selected by `WKInterfaceDevice.current().screenBounds.width`, following the handoff's 49/45/41 mm columns (≥204 pt → 49 mm specs, ≥192 pt → 45 mm specs, else 41 mm specs; smaller/older cases use the 41 mm tier). Governs button height (35/33/30), chevron ⌀ (27/26/23), stepper ⌀ (36/34/31), card height (46/43/37), fonts and gaps. The top zone adds `topNameSize` (15/14/12), `topPercentSize` (11/10.5/9.5) — now the size of the `Exercise X / Y` label and the `Set X/Y` counter — `topSegmentHeight` (3.5/3.5/3) and `topZoneSpacing` (6/5.5/4.5, with the routine↔exercise gap widened by +3) — the name/counter sizes are nudged ~2 pt above the handoff's strict 2× values (13/10.5 at 49 mm) for glanceable legibility during a workout. Defined in `Views/WorkoutScreenStyle.swift` together with the shared button styles.

## Colors
Workout-screen tokens live in `OnyxWatch.Colors` (`OnyxWatchDesignSystem.swift`): `accentGreen` #34E07A (fill, border, checkmark, glow), `surfaceCardActive` #0C2417, `stepperGreen` #1D5138 / `stepperIcon` #63EF9B, `strokeSubtle` #3A3A3C, `textMuted` #98989D, `chipBackground` #1A1A1C / `chipText` #C7C7CC, `glassLabel` #EAFFF2, `doneGradient` #6DFFA8→#2FD873→#17B45A with `textOnDone` #03140A. Background stays pure black (AMOLED).

## Haptics & Interaction
- Complete: `.success`; Undo: `.directionDown` — played once, by `WatchWorkoutViewModel.applyToggleSetCompletion`, so the exercise list and the Action Button intent get the same feedback (the action bar used to play a duplicate copy; consolidated 2026-07-12). Set navigation `.click` is played by `FullScreenSetEditorView.goToPreviousSet/goToNextSet`.
- The handoff specifies `.notification` for the exercise-done moment; deliberately omitted because the ViewModel already plays `.success` for the completing tap and stacking both felt muddy.
- The complete button carries `.handGestureShortcut(.primaryAction)`, so Double Tap (Series 9/10, Ultra 2/3) triggers it; on Ultra models the Action Button completes the current set via App Intents — see [action-button.md](./action-button.md).

## Accessibility
- Complete button: "Complete/Undo set X of Y"; decorative segments hidden from VoiceOver.
- Chevrons: "Previous/Next set" with "Set X of Y" value.
- Steppers: "Increase/Decrease" with the focused field ("Weight"/"Reps") as value.
- Value cards: combined label "WEIGHT. 80 kg" etc., `isSelected` trait on the focused card.

## Architecture
### Components Involved (all watchOS target)
- **`CompactActionBar.swift`**: fused action row (glass complete button + chevrons)
- **`WorkoutTopProgressView.swift`**: top zone — routine level (`Exercise X / Y` label + neutral-gray per-exercise segment bar) and exercise level (name + green-accented `Set X/Y` counter); pure display, reads only its init params (`exerciseName`, `exerciseIndex`/`exerciseCount`, `setIndex`/`setCount`, `exerciseProgress`)
- **`FullScreenSetEditorView.swift`**: screen layout, shared steppers, done-flash state, rest/elapsed toolbar status; passes the current exercise/set indices and counts, and derives `exerciseProgress` (per-exercise completion fractions) from `viewModel.exercises`, into the top zone
- **`CompactValueEditor.swift`**: weight/reps value card (steppers were moved out of it into the editor)
- **`WorkoutScreenStyle.swift`**: `WorkoutScreenMetrics` size tiers, `PressScaleStyle`, `ChevronCircleStyle`
- **`OnyxWatchDesignSystem.swift`**: workout-screen color tokens
- **`ExerciseListView.swift`**: owns the alternative-picker sheet and visible/swipe Swap actions on eligible exercise rows (unchanged); also defines `WorkoutMetricsView` reused for the BPM/kCal column

### How It Works
- `CompactActionBar` receives `isCompleted`, `currentSetIndex`, `totalSets`, `completedSets`, and `showDoneFlash` as parameters; it holds no state of its own.
- Previous/Next only change the displayed set; they never alter completion state.
- The done flash is detected in `FullScreenSetEditorView.toggleSetCompletion()` (the tap completes the exercise's last open set) *before* calling the ViewModel, because the ViewModel immediately auto-advances `currentExerciseIndex`/`currentSetIndex` afterwards; the flash is a local `@State` cleared after 800 ms.
- Single-set exercises show only the capsule (no chevrons, no segments).
- Elapsed time comes from the existing `viewModel.elapsedTimeString` publisher (the handoff suggests `TimelineView`; the existing per-second publisher was kept — no new plumbing). The top-trailing status carries `.offset(y: -8)` to sit on the system clock's centerline (toolbar trailing items natively render ~8 pt lower; the design has back button, clock, and chip on one line).
- The editor is pushed onto the shared `NavigationStack` owned by `ActiveWorkoutView` (`navigationDestination(for: Int.self)` keyed by exercise index); it has no stack of its own and uses the native back button.

## Design Exploration & History
- An earlier iteration (still visible in git history) used a two-tier dock: a segmented navigation rail above a dark "Complete"/"Undo" capsule. It solved the "Next ≠ Complete" confusion but spent vertical space on a separate progress row. The final design fuses progress *into* the button (fill + mini segments) and returns the chevrons to a single row, keeping the verb label per HIG.
- Before that, numeric badges and literal progress dots were rejected (no per-set completion info / cramped at high set counts).
- Simulator review of the first single-row design exposed the semantic problem that motivated the verb label: chevrons beside a status-labelled button read as if Next completed the set. The verb label is retained in the final design.
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
- **Workout status:** Apple recommends displaying elapsed or remaining time during active workouts, so a conditional action must not replace it — the top-trailing slot always shows rest countdown or elapsed time.
- **Swap placement:** The exercise list is the owning context for exercise identity and alternatives. A visible row accessory provides direct access; swipe remains a shortcut.
- **Dead ends:** An inline Swap pill broke the non-scrolling editor layout. Replacing elapsed time with Swap hid persistent status. `secondaryAction` is explicitly unavailable on watchOS. Context menus are unsupported on watchOS and were removed.
- **Compatibility:** Uses `ultraThinMaterial`, gradients, `symbolEffect(.bounce)`, and existing sheet/toolbar APIs within the current watchOS target. No entitlement, permission, persistence, or ViewModel change was required.
- **Sources:** [Apple Human Interface Guidelines — Workouts](https://developer.apple.com/design/human-interface-guidelines/workouts), [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons?changes=latest_1__8), [Gestures](https://developer.apple.com/design/human-interface-guidelines/gestures), [Context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus)
- **Detailed report:** [Watch Set Editor Control Placement Research](../.scratch/watch-set-progress-in-button/ux-control-placement-research.md)

### Targets
- **watchOS**: `GymStreakWatch Watch App` — this is watch-only UI
- **iOS**: Not affected — iOS workout UI uses different components
