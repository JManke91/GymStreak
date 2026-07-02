# Alternative Exercises

## What the feature does

A routine exercise (e.g. Bench Press) can have any number of **alternative exercises** (e.g. Dumbbell Press). Each alternative carries its **own set scheme** (reps/weight/rest), initially seeded as a copy of the primary exercise's sets. During a live workout the user can **swap** the planned exercise for one of its alternatives (or back) as long as no set has been completed — the classic "machine is busy" case. The performed exercise (not the planned one) is what lands in workout history.

## Data model (iOS, `Models.swift`)

```
RoutineExercise (1) ←→ (many) RoutineExerciseAlternative (1) ←→ (many) AlternativeExerciseSet
```

- `RoutineExercise.alternatives: [RoutineExerciseAlternative]?` — cascade delete, `nil` default (CloudKit-compatible; added as a new optional relationship so existing records sync cleanly).
- `RoutineExerciseAlternative`: `routineExercise` (inverse), `exercise` (the substitute `Exercise`), `order`, cascade-deleted `sets`.
- `AlternativeExerciseSet`: reps/weight/restTime/order — intentionally a separate model from `ExerciseSet` so an alternative's scheme is independent of the primary's sets.
- Swap tracking on history: `WorkoutExercise` stores swap metadata (`swappedFrom…` fields, `wasSwapped`) — the recorded name/exerciseId always reflect what was actually performed.

**CloudKit constraints honored**: all relationships optional, all attributes defaulted, no `.unique`, no `.deny` delete rules. Remember the standing rule: deploy the CloudKit schema in the Console before releasing model changes (see memory/`cloudkit-schema-production-deploy`).

## Where users manage alternatives (UI surfaces)

Since 2026‑07‑02 the feature is surfaced consistently in **all three places where an exercise's routine configuration is edited**, using one shared visual language (`arrow.triangle.2.circlepath` icon, minus-button removal, "Add Alternative" row):

1. **Add exercise to existing routine** (`AddExerciseToRoutineView` → `ConfigureExerciseSetsView`): an optional **"Alternative Exercises" section** below the rest-timer section. Picks are held as `[PendingAlternative]` in `@State` and materialized on Save via `RoutinesViewModel.addAlternative(_:to:copying:)` after the `RoutineExercise` is attached to the routine.
2. **Create new routine** (`CreateRoutineFlow`: `ConfigureExerciseView`): same section. Picks travel as `PendingRoutineExercise.alternatives: [PendingAlternative]` and are materialized in `CreateRoutineView.saveRoutine()` (models inserted into the context **before** relationships are wired — see pitfalls below).
3. **Routine detail** (`RoutineDetailView`): per-exercise ⋯ menu → "Add/Edit Alternatives" switches the expanded card into an inline **alternatives edit mode** (`alternativesEditContent`): remove alternatives, add via `AddAlternativeView` sheet, and tap an alternative to edit its own sets inline.

**Set editing is inline, in every flow — no separate page.** Tapping an alternative row expands `AlternativeSetsInlineEditor` in place (expandable set rows with reps/weight steppers, apply-to-all banner, add/remove set, shared rest timer). Right after an alternative is picked, its row auto-expands so reps and weight can be defined immediately (`expandedAlternativeId` set by the picker's `onSelect` in flows 1/2; `AddAlternativeView.onAdded` in flow 3).

**Seeding**: set count, reps and rest carry over from the primary, but **weight starts at 0** — a different exercise almost always needs a different weight, so copying it would be a wrong prefill. (Applies to the pending flows via `PendingAlternative.init(seededFrom:)` and to flow 3 via `RoutinesViewModel.addAlternative`; when Flow 1 saves user-edited pending sets, their weights are kept.)
   - Discoverability: when an exercise has **zero** alternatives, its collapsed row shows a tappable tertiary "Add Alternative" line (`ExerciseHeaderView`) in the same slot where the "%d alternatives" count appears once alternatives exist. Before this, the zero state had no visible affordance at all — the feature was only findable inside the ⋯ menu.
   - Visibility: the **expanded** exercise card (normal mode, `normalSetContent`) shows a read-only "Alternatives" block after the sets, listing each alternative (icon, name, sets count). Tapping one enters alternatives edit mode with that alternative's inline editor expanded. Before this, alternatives were invisible outside the edit mode — user feedback flagged it.

### Shared components

- `Views/Routines/AlternativeExercisePicker.swift` — reusable picker **content** (search, exclusion of primary + already-added alternatives, same-muscle-group-first sorting). Used in two presentations:
  - Pushed via `.navigationDestination(isPresented:)` from both configure screens (flows 1/2).
  - Wrapped in a `NavigationStack` + Cancel by `AddAlternativeView` for the routine-detail sheet (flow 3).
- `Views/Routines/AlternativeSetsInlineEditor.swift` — the inline set editor used in **all three flows**. Generic over the `AlternativeEditableSet` protocol, to which both `ExerciseSet` (pending, uninserted) and `AlternativeExerciseSet` (persisted) conform; persistence is injected via `onSetChanged`/`onAddSet`/`onRemoveSet` callbacks (no-ops or array mutations pre-save, `RoutinesViewModel` calls in routine detail). Includes the `ApplyToAllBanner` so a changed reps/weight value can be applied to all sets in one tap, and follows the `guard expandedSetId == set.id` pattern in `onUpdate` callbacks (see the SwiftUI animation/onChange bug pattern in project memory).
- `Views/Routines/PendingAlternative.swift` — `@Observable` class: `exercise` + editable `sets` of **uninserted** `ExerciseSet` instances, seeded at pick time.
- `Views/Routines/PendingAlternativesSection.swift` — the "Alternative Exercises" form section for the pre-save flows (expandable rows with remove buttons and sets count + Add row + explanatory footer). Operates on `Binding<[PendingAlternative]>`; the `RoutineExerciseAlternative` models don't exist until save.
- `Views/Routines/AddAlternativeView.swift` — thin sheet wrapper for the persisted-`RoutineExercise` case; delegates to the shared picker and `RoutinesViewModel.addAlternative`, reporting the created alternative via `onAdded` so the presenter can chain into the set editor.

### ViewModel (`RoutinesViewModel.swift`, "Alternative Exercise Management")

`addAlternative(_:to:copying:)` (`@discardableResult`, returns the created alternative; seeds sets from `copying` if given — keeping weights — else from the primary's `setsList` with weight 0), `removeAlternative(_:from:)` (reorders remainder), `addSet(to:)` (`@discardableResult`, returns the new set so the inline editor can expand it), `removeSet(_:from:)`, `updateSet(_:)` for `AlternativeExerciseSet`.

## Workout swapping (consumption side)

- **iOS** (`WorkoutViewModel` "Alternative Exercise Swapping", `ActiveWorkoutView` `ExerciseCard`): the exercise card header shows a **labeled tint-capsule "Swap" pill** (icon + text, `textOnTint` foreground) while swapping is allowed — an earlier bare `arrow.triangle.2.circlepath` icon button proved not self-explanatory (users read the glyph as refresh/sync). Tapping opens `SwapExercisePickerView` (`Views/Workout/SwapExercisePickerView.swift`), a **compact detent sheet** (`.height(320)` + `.large`, drag indicator) replacing the earlier `confirmationDialog`: a non-selectable "Current" row for orientation, then one row per target with name, muscle group and the target's **own set scheme** (e.g. "Chest · 3×10 · 20kg"); the revert row is phrased "Revert to X" with an `arrow.uturn.backward` icon. `SwapTarget` carries a `setScheme` string computed in `swapTargets(for:)` (count × reps range, plus weight only when uniform and non-zero — alternative weights often start at 0).
  - **Lock is communicated, not hidden**: once a set is completed, the pill stays visible **on the current exercise only** in a gray locked state (`lock.fill`); tapping explains via alert that un-completing the set re-enables swapping (`canSwap` is `completedSetsCount == 0`, and set completion is reversible). Non-focused cards hide the affordance to avoid clutter.
  - The persistent "Swapped from X" caption is **tappable**: it reopens the picker (revert row first) or, when locked, shows the same explanation alert.
- **watchOS**: alternatives ride along in the WatchConnectivity routine payload (`WatchModels.swift` on both targets — `WatchExerciseAlternative` with its own set scheme). `WatchWorkoutViewModel` implements the same swap rule (`canSwap`: no completed sets && alternatives exist) plus revert, and resets `currentSetIndex` when the current exercise is swapped (the set scheme is rebuilt). Completed workouts sent back to iOS carry the swap metadata.
  - Watch swap UI (three entry points, all funneling into `WatchSwapPickerView`): a **visible "Swap" pill** on the set-tracking screen (`FullScreenSetEditorView`, shown only while `canSwap`), plus swipe-left and long-press on rows in `ExerciseListView`; rows with alternatives show a small ↻ indicator next to the name. The pill is the primary affordance — the gestures alone proved undiscoverable (user feedback), and long-press is a dead pattern on modern hardware (Force Touch removed since Series 7). The pill label was renamed from "Alternative" (noun, begs "alternative to what?") to the verb "Swap" — the same vocabulary as iOS. Picker rows show muscle group **and the target's set scheme** ("Chest · 3×10"), with an `arrow.uturn.backward` icon on the revert row (matched by `exerciseId == plannedExerciseId`). On watch the affordance simply hides once locked (no gray state) — watch controls are expected to appear/disappear contextually (cf. Apple Workout's Pause↔Resume) and screen space is contended.
  - `Views/ExerciseSetView.swift` is **unused legacy** (nothing instantiates it; `FullScreenSetEditorView` is the live set screen) — don't add features there.
- Watch has **no management UI** — alternatives are configured on iOS only and synced over (consistent with the WatchConnectivity-based routine sync, see `docs/watch-sync.md`).

## Design decisions

- **An alternative's reps/weight are editable immediately at add time, in all flows.** An initial iteration (same day) deferred set editing in the configure flows to routine detail, reasoning the seeded copy had nothing to edit — user feedback overturned this: the whole point of an alternative (e.g. dumbbell instead of barbell press) is usually a *different* weight.
- **Editing is inline (expand-in-place), not on a separate page/sheet.** Two earlier iterations used a pushed page (`PendingAlternativeSetEditView`, deleted) and a sheet (`AlternativeSetEditView`, deleted) — user feedback: bouncing to a separate page fragments the flow. Expand-in-place is also the app's established interaction language (routine detail sets, configure-screen sets). One shared component (`AlternativeSetsInlineEditor`) now serves all flows; restoring the old views = git history around 2026-07-02.
- **Weight is not copied from the primary when seeding** (reps/sets/rest are) — user feedback: copying the weight "does not make sense" for a different exercise.
- **Adding alternatives is strictly optional** — zero mandatory taps added to the add-exercise path; the section sits last, after Sets and Rest Timer, mirroring Apple's "optional secondary sections in creation forms" pattern (Calendar new-event: Alert/Invitees/Notes).
- **Picker presentation differs by context, content is identical**: pushed in the configure flows (they already live inside a sheet/full-screen cover — HIG warns against sheet-over-sheet), presented as a sheet from RoutineDetailView (no nesting there). 
- **No `ContentUnavailableView` for the empty alternatives section** — that pattern is reserved for primary empty states; an optional sub-section only gets the footer caption + Add row.
- The alternatives indicator on routine rows is monochrome (color is reserved for superset grouping).
- **In-workout swap affordance is a labeled pill + rich sheet, not a menu (2026-07-02 redesign).** Options evaluated and rejected for the iOS trigger:
  - *Bare icon button* (the original): `arrow.triangle.2.circlepath` reads as refresh/sync, not "substitute" — the core complaint. A text label, not a better glyph, is what fixes comprehension (`arrow.2.squarepath` would be the semantically correct swap glyph if an icon-only affordance ever returns).
  - *Tappable exercise title with `chevron.up.chevron.down`* (Music/Mail `ToolbarTitleMenu` idiom): rejected — that idiom signals identity/context switching, the card header is already crowded (badge, name, subtitle, superset badge, checkmark, delete), and a static word with a tiny chevron is as easy to miss as the old icon.
  - *Inline chips / segmented picker*: rejected — costs vertical space in every card for an affordance only relevant before the first set; segmented control can't carry a set-scheme subtitle.
  - *SwiftUI `Menu` with subtitle rows*: viable (two-`Text` labels render subtitles, iOS 14+), but menu rows are small for mid-workout, one-handed use; a detent sheet with ≥52pt rows won. `confirmationDialog` (the original picker) is meant for confirm/destruct choices and can't show per-row detail.
  - No extra confirmation step on selection: zero sets are logged when swapping is possible, so nothing can be lost, and revert is one tap away — the deliberate open-sheet-and-tap is confirmation enough.
  - Swap targets are shown with their own set scheme because that's the decision-relevant fact (why you'd pick dumbbell over barbell); weight appears only when uniform across sets and non-zero (alternatives seed at 0).

## Research findings / gotchas (do not re-research)

- **SwiftData relationship timing**: setting a relationship (or appending to a to-many array) between two `@Model` objects when either side is not yet inserted in a `ModelContext` can crash with *"Illegal attempt to establish a relationship … between objects in different contexts"* (Apple Forums thread 738961). Hence both pre-save flows keep picks as `PendingAlternative` values (whose `ExerciseSet` instances are created but never inserted — the same pre-existing pattern the configure screens use for the primary's sets) and materialize `RoutineExerciseAlternative`/`AlternativeExerciseSet` only inside the save transaction, inserting models before wiring relationships. CloudKit's "all relationships optional" rule does **not** exempt you from this ordering rule — they are separate constraints.
- **iOS 18 `NavigationStack` + `.searchable` regression (FB15221588**, Apple Forums thread 764306, acknowledged by DTS): after activating search in a stack view, a programmatic **pop-to-root** (clearing the `NavigationPath`) silently fails. The alternative picker uses `.searchable` and is pushed — so selection handlers pop exactly **one** level (reset the `isPresented` flag / `dismiss()`), never the whole path. Keep it that way.
- **Avoid pop-then-push / sheet-chaining for the post-pick editor**: an intermediate iteration popped the picker and pushed a separate editor page (needed a 0.4s `asyncAfter` delay to sequence the transitions) and chained two sheets via `onDismiss` in routine detail. The inline editor made both hacks unnecessary — after picking, only state changes (`expandedAlternativeId`), no second navigation transition. If a separate editor page ever returns, remember: same-update pop+push is unreliable on iOS 18, and a sheet cannot present while another dismisses.
- **`onAppear` re-fires when popping back** from the pushed picker. `ConfigureExerciseView` loads `existingSets` in `onAppear`; without a `hasLoadedInitialState` guard this reset in-progress set edits when returning from the picker (bug caught during implementation, guard added).
- **Sheet-over-sheet avoided** per HIG ("display only one sheet at a time from the main interface"); the configure flows push the picker onto their existing stack instead — which also matches the codebase's "navigation over sheets for main paths" convention.

## Deliberate omissions

- No dedicated empty-state hint in the live workout when a swap is attempted on an exercise without alternatives — the swap button simply doesn't appear. Deemed acceptable for now; revisit if support questions come in.
- Watch-side management UI intentionally not built (iOS is the single configuration surface).
