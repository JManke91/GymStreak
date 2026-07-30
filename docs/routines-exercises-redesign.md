# Routinen & Übungen Redesign

## What it is
A full visual redesign of the **Routines** (Routinen) and **Exercises** (Übungen) tabs to match the editorial dark style already shipped for the History/Verlauf tab (see [history-redesign.md](./history-redesign.md)). All existing functionality is preserved — this is a presentation-layer redesign, not a behavioral change. No SwiftData schema changes.

Target: **iOS app only** (`GymStreak`). The watch target is untouched.

Source of truth for the visual spec: the Claude Design project — *"Routinen & Übungen Redesign.html"* (v1, imported 2026-07-03) and *"Routinen und Uebungen Redesign v2.html"* (v2, imported 2026-07-28, **routine detail only**). The design's React/JSX mock (`gs-data.jsx`, `gs-shared.jsx`, `gs-routinen.jsx`, `gs-uebungen.jsx`) informed the SwiftUI implementation; colors, spacing, and copy were adapted to the app's real data model and existing DesignSystem.

## Scope decisions (confirmed with the user)
- **Both tabs** redesigned (Routinen + Übungen). History was already done.
- **Native `TabView` kept** — the design's floating pill tab bar was *not* adopted, to avoid app-wide regressions and keyboard-avoidance loss. Only screen content changed.
- **All existing features kept and restyled** — supersets, rep ranges + progressive overload, per-set reorder, alternative exercises, multi muscle groups. The mock's simpler data model did not drive feature removal.
- **"Up Next" hero card included** — the least-recently-trained routine is promoted with a full-width start button.

### v2 scope decisions (2026-07-28, confirmed with the user)
v2 only redesigns the **routine detail**; the Routinen list, Übungen tab, pickers and sheets were already shipped by v1 and are unchanged. Where the mock's simpler data model collided with shipped functionality, the user chose:
- **Set rows**: adopt the mock's always-editable stepper rows, **but** keep each value typeable (tap the number → numeric keyboard) so precise weights stay reachable — the mock's ±2.5 kg-only steppers would have made e.g. 38.25 kg unenterable. The "apply to all sets" banner survives, moved under the last-edited row. Set **reordering** keeps its own mode behind the card menu (stepper rows can express removal but not order).
- **Alternatives**: adopt the mock's flat list; tapping a row expands that alternative's own chips + set editor in place. Retires v1's variant-switcher pills, `AlternativeFocusedEditor` and the `AlternativesBrowseView` sheet. Removal still asks for confirmation (`alternatives.remove.*`) — the mock removes silently.
- **Supersets** are absent from the mock. The per-card **ellipsis menu is deliberately kept** (a documented deviation from the design) so superset create/edit and the alternatives doorway stay one tap away; the long-press context menu still mirrors them.
- **Delete an exercise**: adopt the mock's immediate delete + undo toast, replacing the confirmation alert.
- **Not in the mock, kept as-is**: the schedule card (`RoutineScheduleCard`), the progressive-overload banner, superset badges / line indicators / link buttons.

## How it works

### Routines tab (`RoutinesView`)
- `NavigationStack` on a `DesignSystem.Colors.background` canvas, native nav bar hidden.
- Large rounded title + subtitle (`routines.header_meta`: count + last-trained relative date) + a tinted `+` button.
- **Hero card** (`RoutineCardView` with `isHero: true`): `RoutinesViewModel.upNextRoutine` = the routine with the oldest (or missing) last-trained date. Tinted gradient background, overlapping exercise avatars, muscle chips, a full-width "Workout starten" button.
- **"Alle Routinen"** section: the remaining routines as regular `RoutineCardView`s (inline circular play button).
- Each card is a `NavigationLink(value: routine.id)` → `RoutineDetailView`, resolved via `.navigationDestination(for: UUID.self)`. A `contextMenu` offers Duplicate / Delete.
- Dashed "Neue Routine" tile → `CreateRoutineView` (unchanged flow).
- Start button → `WorkoutViewModel.startWorkout` + `fullScreenCover(ActiveWorkoutView)`.

### Routine detail (`RoutineDetailView` + `RoutineDetailComponents`)
Rewritten from a `List(.insetGrouped)` with a nav-bar Edit button into a **`ScrollView` + `LazyVStack`** on the dark canvas with a custom top bar (back / Bearbeiten / ellipsis menu). Every exercise is a self-contained rounded **card** instead of a grouped row.
- **Container: `ScrollView` + `LazyVStack`, not `List` (2026-07-07).** Originally `List(.plain)`. `List` snaps intra-row height changes (Apple-DTS-confirmed iOS-18 limitation), so expanding a card/set looked like a re-render, not a growth. Moved to `LazyVStack` (per-child padding replaces `listRowInsets`; cards use `.frame(maxWidth:.infinity)` to stretch) where height interpolates. Card expansion now uses `.transition(.opacity.combined(with:.move(edge:.top)))` inside `withAnimation(spring)`, clipped by the card's `.clipShape`. This applies to the **browsing** container only — drag-to-reorder went back to `List.onMove` in a separate sorting-mode container on 2026-07-29 (see below).
- **Top bar**: back chevron, **Sortieren**/Fertig toggle (v2 — the mode is purely reorder + remove, so it is no longer called "Bearbeiten"), ellipsis menu (Rename via alert, Duplicate, Delete).
- **Swipe-back gesture fix (2026-07-11)**: hiding the system nav bar via `.toolbar(.hidden, for: .navigationBar)` (needed for the custom top bar above) has a SwiftUI side effect — `UINavigationController`'s default delegate refuses `interactivePopGestureRecognizer` whenever there's no visible system back-button affordance on the top view controller, so edge-swipe-to-back silently stopped working (only the custom back chevron worked). No pure-SwiftUI fix exists (confirmed: modifier ordering, `.navigationBarBackButtonHidden` variants, and iOS 18's `UIGestureRecognizerRepresentable` all fail to restore it — the last one creates a *new* gesture recognizer rather than reinstating the system-owned one). Fixed via `GymStreak/Extensions/View+SwipeBack.swift`: a `UIViewControllerRepresentable` (`SwipeBackEnabler`) that walks up to the hosting `UINavigationController` and reassigns `interactivePopGestureRecognizer.delegate` to a permissive `UIGestureRecognizerDelegate` (guarding against popping past the stack root), reapplied on every `updateUIViewController` pass since UIKit reasserts its own delegate around push/pop transitions. Exposed as `.swipeBackEnabled()`, applied in `RoutineDetailView` right after `.toolbar(.hidden, for: .navigationBar)`. The same hidden-nav-bar + custom-back-button pattern exists in `ExercisesView`, `ExerciseDetailView`, `HistoryView`, `PeriodRecapView`, and `ExerciseProgressChartView` — not yet audited/fixed there, only `RoutineDetailView` was reported broken.
- **Title block**: routine name, horizontally-scrolling muscle chips + meta (`routines.card_meta`).
- **Exercise card** (`normalExerciseCard`, **redesign v2 · 2026-07-28**): `ExerciseHeaderView` (avatar, name, set summary, equipment tag, alternatives avatar stack, actions menu, superset badge) + an always-visible **parameter chip strip** + expandable body.
  - **Chip strip** (`ExerciseParameterChips` in `RoutineParameterChips.swift`): a *Pause* chip and a *Ziel* chip (ghost/dashed when no rep goal is set). Tapping a chip opens its editor **inline directly beneath the strip** — `RestTimeInlineEditor` (60/90/120/150s presets + a ±15s `CompactStepper` + enable/disable) or `RepRangeInlineEditor` (4–6 / 8–12 / 12–15 segments + "Eigen" min/max steppers + "Kein Ziel"), both in `RoutineParameterEditors.swift`. These replaced `RestTimerConfigView` / `RepRangeConfigView` inside the card; the chips work whether the card is expanded or not. For a superset member the Pause chip reads and writes the **group** rest time (`supersetRestTime` / `updateSupersetRestTime`), so any member can change it — v1 only allowed the first member.
  - **Expanded body**: a `SetsSectionLabel` ("SÄTZE") + `RoutineSetsEditor` — **always-editable** rows (`RoutineSetStepperRow`: remove button, index, reps stepper, weight stepper) instead of v1's tap-to-expand `RoutineSetRowView`. Each numeric value is a `TextField` styled as text, so exact values stay typeable; the shared `keyboardDoneBar` at screen level dismisses the pad. The "apply to all sets" banner now appears under whichever row was edited last (`recentlyEditedSetId`) rather than inside an expanded editor. Then the **Alternativen** section (`RoutineAlternativesSection`), rendered even when empty so the feature stays discoverable.
  - The `ScrollViewReader` + `.id(routineExercise.id)` per card is retained so `openAlternatives(for:)` can scroll a target card into view.
- **Sortieren mode (v2)**: replaces v1's wiggle/minus-circle edit mode. Cards collapse to `RoutineSortingRow` (drag affordance, avatar, name + set summary, trash), a **persistent** tinted hint banner (`routine.sort_hint`) sits above the list instead of v1's one-shot `hasSeenReorderHint` toast, and the start-workout CTA is hidden.
- **The screen has two containers (2026-07-29).** `browsingModeContent` is the `ScrollView` + `LazyVStack` described above; `sortingModeContent` is a fixed header + a real **`List` with `.onMove(perform:)`**. The `List`-snaps-height objection does not apply to sorting mode — its rows are fixed-height and nothing expands there.
  - **Why: the hand-rolled reorder was broken.** v2 initially reordered via `.onDrag` / `.onDrop(of:delegate:)` + a `DropDelegate` in `ExerciseReorder.swift`, with a `draggingId: UUID?` binding cleared in `performDrop`. On device, dropping a row left it permanently dimmed and killed dragging for the whole list: **`performDrop` never fires when the drop lands outside a registered row target** (the gutter between rows, or a cancelled drag), so `draggingId` was never reset. This is a known, still-current SwiftUI gap — see Apple Developer Forums [thread 758015](https://developer.apple.com/forums/thread/758015), where an Apple engineer points at the missing *container-level* drop delegate.
  - **Dead ends considered and rejected:** (1) patching the delegate with a full-bleed catch-all `dropDestination` on the container (the community `reorderableForEachContainer` idiom) — works, but keeps a hand-rolled lifecycle plus a soft-deprecated API for no gain here; (2) Apple's purpose-built successor `View.reorderContainer(for:itemID:isEnabled:move:)` / `DynamicViewContent.reorderable()` / `dragContainer` — this is the *right* long-term answer for reordering in a lazy stack, but it is **iOS 27.0+ (Beta)** and the app targets iOS 26.1, so revisit when the deployment target moves. `.onDrag`/`.onDrop(of:delegate:)` are deprecated (not removed); do not build new reorder code on them.
  - `List.onMove` owns the whole drag lifecycle internally, so there is no drag state to leak: `draggingId`, `persistReorder` and `ExerciseReorder.swift` are gone. `moveExercises(from:to:)` only forwards the offsets to `RoutinesViewModel.moveRoutineExercises(from:to:in:)`, which owns the renumber-and-save transaction like every other multi-object edit here.
  - The mode's container, hint and move action live in `RoutineDetailView+Sorting.swift`.
  - **Trap fixed before ship:** with two containers, removing the *last* exercise while sorting left the screen with no way out — the Fertig toggle was gated on a non-empty routine and sorting mode has no empty state. `removeExercise` now clears `isSorting` when the routine becomes empty, and the toggle's gate also accepts `isSorting`.
- **Delete with undo (v2)**: removing an exercise no longer asks for confirmation. `RoutinesViewModel.removeRoutineExercise` returns a `RemovedRoutineExerciseSnapshot` (a value copy of the exercise, its sets, rep range, superset membership and alternatives-with-set-schemes — SwiftData deletion cascades, so it must be captured *before* the delete), an `UndoToast` offers "Rückgängig" for 5 s, and `restoreRoutineExercise` re-creates the exercise at its original index. The toast timer is a cancellable `Task`, cancelled on undo and on `onDisappear`.
- **Preserved subsystems** (unchanged logic, restyled containers): progressive-overload banner, superset link buttons / selection edit mode / context menu, schedule card, "apply to all" banners.
- **Removed 2026-07-29 — the "Sätze bearbeiten" mode.** v2 initially kept v1's set-edit mode behind the card menu for set *reordering*. On device it read as a bug: tapping it replaced the always-editable set rows with a strictly weaker reorder-only list and blocked the header from collapsing the card, so the UI looked stuck. The menu entry, the mode (`setEditExerciseId`, `setReorderContent`) and `RoutinesViewModel.moveExerciseSets` were deleted. **Set reordering is gone as a capability** — see `superset-feature.md` for how to restore it.
- **Per-card display struct**: `RoutineExerciseCardDisplay` resolves name, avatar, set summary and alternative avatars in the `ForEach` body of `exerciseRows` / `sortingModeContent`, and the header and sorting rows take that value struct — so no *row* body walks `setsList` / `alternativesList` / `alternative.exercise` or calls a formatting service. Note the honest limit: it is rebuilt whenever `RoutineDetailView.body` is re-evaluated (which `expandedExerciseId`, `openParameters`, `expandedAlternativeId` and the screen-wide `@FocusState` all trigger), for the visible rows only. If that ever measures as a hang, cache it as `[UUID: RoutineExerciseCardDisplay]` in `@State` keyed off the routine's change count.
- **Superset styling resolved in one pass**: `supersetStyling(for: ordered)` returns `[UUID: SupersetCardStyling]` — colour, position, total and line position for every card — built from a single grouping of the routine. Calling the old per-card variant inside the `ForEach` filtered and sorted the whole routine once per card (O(n²)) and rebuilt the label map each time.
- **Bulk edits persist once**: `updateRoutine` saves *and* refetches all routines *and* re-derives last-performed dates from every session, so a per-set save loop would run that cascade N times for one tap. `RoutinesViewModel.updateRestTime(_:for:)` and `applyToAllSets(from:field:in:)` (both with a `RoutineExercise` and a `RoutineExerciseAlternative` overload) write every set first and save once.
- **Sticky CTA**: gradient-backed "Workout starten" via `safeAreaInset(edge: .bottom)`; replaced by the superset-edit toolbar when a superset edit is active.

### Exercises tab (`ExercisesView`)
- Same dark canvas + hidden nav bar. Header (`exercises.header_meta`), `RedesignSearchBar`, two horizontal filter-pill rows (muscle **category** + equipment), and exercises grouped by muscle category with colored-dot section headers. The list `ScrollView` uses `.scrollDismissesKeyboard(.interactively)` so dragging the list hides the search keyboard.
- **Search keyboard dismissal** (2026-07-11): previously the keyboard could only be dismissed via the return key. Now three affordances, everywhere `RedesignSearchBar` is used (Exercises tab + `RoutineExercisePickerView`):
  - **Primary**: `keyboardDoneBar(isFocused:)` (View extension in `RedesignControls.swift`) — a floating Liquid Glass "Fertig" capsule (`action.done` + `keyboard.chevron.compact.down` Label, `.buttonStyle(.glassProminent)` tinted with `DesignSystem.Colors.tint`, label in `textOnTint` per the contrast rule) pinned directly above the keyboard via a conditional `.safeAreaInset(edge: .bottom)` (the keyboard shrinks the safe area, so the inset rides on top of it). `.glassProminent` is the Apple-recommended style for a lone floating glass action (iOS 26.0+); plain `.regular` glass without tint washes out on the near-black canvas, and hand-rolled `.glassEffect(in:)` has a beta bug ignoring custom shapes — use the button styles. The screen owns a `@FocusState` and passes its projection into both `RedesignSearchBar` (as `FocusState<Bool>.Binding`) and `keyboardDoneBar`. **Placement rule**: attach the bar to a container that does NOT itself carry `.scrollDismissesKeyboard(.interactively)` — FB13296535 makes `safeAreaInset` content float mid-screen during interactive dismissal when both sit on the same `ScrollView` (in `ExercisesView` the bar is on the `ZStack`, the scroll-dismiss on the inner `ScrollView`).
  - **Fallback**: inline "Fertig" button inside the search bar itself while focused.
  - Drag-to-dismiss via `.scrollDismissesKeyboard(.interactively)` on the exercise list.
  - **Dead end — do not re-try**: `ToolbarItemGroup(placement: .keyboard)` did NOT render on iOS 26, neither attached to the TextField nor recommended at stack level — known SwiftUI bug family (FB13209435/FB15588827: keyboard toolbar items fail when the `.toolbar` modifier is nested inside a `NavigationStack`, `Spacer()` in the group is a documented trigger) plus the open iOS 26 Liquid Glass regression FB22938104 (item renders flush/invisible against the keyboard). `safeAreaInset` bypasses the toolbar-merge pipeline entirely. Sources: Apple forums threads 736040, 709227, 797250; feedback-assistant/reports#437.
- `ExerciseLibraryRowView`: avatar, name, equipment tag, "in N routines" count (`ExercisesViewModel.routineUsageCount`), muscle chip. `NavigationLink(value: exercise.id)` → `ExerciseDetailView`.
- DEBUG-only "delete all" and the standard add/delete confirmation alerts are retained.

### Exercise detail (`ExerciseDetailView`)
- Custom top bar with ellipsis menu (Edit / Delete). Hero (large avatar + muscle-colored uppercase label + name), info card (muscle chips + equipment), and a **"Verwendet in"** list built from `exercise.routineExercises` (primary) + `exercise.alternativeUses` (alternative), showing a per-routine set summary and an "Alternative" chip.
- Editing now reuses `AddExerciseView` (via `exerciseToEdit:`); the old inline-editing `ExerciseDetailView` form and the separate `EditExerciseView` were removed.

### Add / edit exercise (`AddExerciseView`)
- One component now handles both create and edit (`exerciseToEdit:` optional). Sheet header (Abbrechen / Speichern) or nav-toolbar save depending on `presentationMode`.
- Name card, muscle-group pills grouped by category (multi-select, `FlowLayout` wrapping), equipment tiles, and a **live preview row** of the resulting library entry.

### Exercise picker (`RoutineExercisePickerView`)
- Restyled to the dark canvas: `RedesignSearchBar`, muscle-category filter pill row, "Verfügbar" section (tap → `ConfigureExerciseSetsView`), "Bereits in Routine" section (dimmed + check), dashed "Neue Übung erstellen" button.
- **Decoupled from `Routine` (2026-07-11, unified-picker ticket 01):** the picker no longer takes `routine:`/`viewModel:`; it takes `alreadyAddedExercises: [Exercise]` plus `onExerciseConfigured: (Exercise, [ExerciseSet], [PendingAlternative]) -> Void` and owns no persistence. `ConfigureExerciseSetsView` finalizes set restTime/order and hands the result to that callback instead of writing to the routine. Persistence for the existing-routine flow lives in `RoutinesViewModel.addConfiguredExercise(_:to:sets:alternatives:)`, invoked from `RoutineDetailView`'s sheet closure.
- **Unified across both flows (2026-07-11, unified-picker ticket 02):** renamed `AddExerciseToRoutineView` → `RoutineExercisePickerView` (file moved to `Presentation/Views/Routines/RoutineExercisePickerView.swift`; the plain name `ExercisePickerView` is already taken by the single-select swap picker in `Views/Exercises/`, used by `ActiveWorkoutView`). The create-routine flow now presents the same picker as a sheet from `CreateRoutineView` (`onExerciseConfigured` appends a `PendingRoutineExercise`; save still goes through `RoutinesViewModel.createRoutine`). The old `CreateRoutineFlow/ExerciseSelectionView.swift` (SwiftData `@Query` in a View — architecture smell) was deleted along with its `exercise_selection.*` localization keys. Dismiss behavior is deliberately one-exercise-per-sheet-visit in both flows (the old create-flow multi-add-per-visit was dropped for consistency).
- **Muscle-group filter (2026-07-11, unified-picker ticket 03):** the same `FilterPillButton` row as the Exercises tab ("Alle" + one pill per category present in the library, colored via `MuscleGroups.categoryColor(for:)`) sits below the search bar. Because the picker is shared, both flows get it. Filtering fully reuses `ExercisesViewModel`: the picker dropped its private repository fetch + inline search filter and instead flattens `ExercisesViewModel.sections(searchText:categoryKey:equipment:)` (equipment always `nil` — the equipment filter was deliberately not requested for the picker), then applies its own Available / Already-in-Routine partition on top. Side effects: the picker list is now ordered by anatomical category then name (previously repository order), and search matches localized muscle names (previously raw English keys). The formerly `ExercisesView`-private `categoryColor(for:)` helper moved to `MuscleGroups.categoryColor(for:)` in `DomainColorStyling.swift` so both pill rows share it. No new localization keys were needed (`filter.all`, `muscle_category.*` already exist in en+de).
- **Deliberate omission — set-config screens NOT unified:** `ConfigureExerciseView` (in `CreateRoutineView`'s flow) still duplicates set-configuration UI with the picker's `ConfigureExerciseSetsView`; it remains solely for EDITING an already-added pending exercise in the create-routine draft. The user chose a 3-slice scope for the unified-picker feature (decouple → unify entry → filter + polish), and merging the two config screens was out of scope. To pick it up later: fold `ConfigureExerciseView`'s edit-existing-pending-exercise case into `ConfigureExerciseSetsView` (which already handles sets, rest time, and pending alternatives) and delete `ConfigureExerciseView`; the original tickets live under `.scratch/unified-exercise-picker/issues/`.

## Architecture

### New files
```
GymStreak/Domain/Services/RoutineMetricsService.swift            Pure metrics: totalSets, estimatedDurationMinutes, primaryMuscleGroups, uniformSetScheme
GymStreak/Presentation/Views/Components/ExerciseVisuals.swift    ExerciseAvatarView, MuscleChipView, EquipmentTagView, MetaChipView
GymStreak/Presentation/Views/Components/RedesignControls.swift   RedesignSearchBar, FilterPillButton, DashedCreateButton, FlowLayout
GymStreak/Presentation/Views/Routines/RoutineCardView.swift      Hero + regular routine card
GymStreak/Presentation/Views/Routines/RoutineDetailComponents.swift  SetsSectionLabel, ExerciseHeaderView, RoutineSortingRow, UndoToast
docs/routines-exercises-redesign.md

# redesign v2 (2026-07-28) — routine detail only
GymStreak/Presentation/Views/Routines/RoutineParameterChips.swift    ExerciseCardParameter, ExerciseParameterChips, ParameterChipButton
GymStreak/Presentation/Views/Routines/RoutineParameterEditors.swift  CompactStepper, ParameterEditorPanel, RestTimeInlineEditor, RepRangeInlineEditor
GymStreak/Presentation/Views/Routines/RoutineSetsEditor.swift        AlternativeEditableSet, RoutineSetStepperRow, RoutineSetsEditor
GymStreak/Presentation/Views/Routines/RoutineAlternativesSection.swift  Flat alternatives list + per-alternative inline editor
GymStreak/Presentation/Views/Routines/RoutineDetailView+Supersets.swift Superset helpers extracted out of RoutineDetailView
GymStreak/Presentation/ViewModels/RemovedRoutineExerciseSnapshot.swift  Value copy for the delete-undo toast
GymStreak/Presentation/Helpers/RoutineExerciseCardDisplay.swift      Per-card display values, resolved once
GymStreak/Presentation/Helpers/WeightFormatting.swift                Locale-aware, trailing-zero-free weight strings
GymStreak/Presentation/Helpers/SetSummaryFormatting.swift            "3 × 6 Wdh. · 90 kg" / "3 Sätze · max 90 kg"
```

### Modified files
```
RoutinesView.swift            Rewritten (hero + card list)
RoutineDetailView.swift       Rewritten body; superset/rep-range/alternatives logic preserved
ExercisesView.swift           Rewritten (filters + grouped library)
ExerciseDetailView.swift      Rewritten (hero + info card + used-in); edits via AddExerciseView
AddExerciseView.swift         Rewritten; now also handles editing (exerciseToEdit:)
RoutineExercisePickerView.swift  (ex AddExerciseToRoutineView.swift) Picker restyled + muscle-category filter pills; filtering via ExercisesViewModel.sections; ConfigureExerciseSetsView unchanged
RoutinesViewModel.swift       + lastPerformedByRoutine, upNextRoutine, refreshLastPerformedDates, duplicateRoutine; v2: removeRoutineExercise returns a snapshot, + restoreRoutineExercise, updateRestTime(_:for:), applyToAllSets(from:field:in:)
ExerciseVisuals.swift         v2: + ExerciseAvatarStack (overlapping avatars + "+N")
RedesignControls.swift        v2: DashedCreateButton gained a `compact` in-card variant
PendingAlternativesSection.swift / ConfigureExerciseView.swift / RoutineExercisePickerView.swift  v2: use RoutineSetsEditor + a shared value-focus flag for the keyboard Done bar
ExercisesViewModel.swift      + routineUsageCount(for:)
DomainColorStyling.swift      + MuscleGroups.color(for:) and categoryColor(for:) — muscle category → color mapping (Presentation)
TimeFormatting.swift          + lastTrainedLabel(for:) relative date
Resources/{en,de}.lproj/Localizable.strings  New keys (see below)
```

### Deleted files
```
GymStreak/Presentation/Views/Exercises/EditExerciseView.swift   Superseded by AddExerciseView editing mode
GymStreak/Presentation/Views/Routines/CreateRoutineFlow/ExerciseSelectionView.swift   Superseded by the unified RoutineExercisePickerView (ticket 02)

# redesign v2 (2026-07-28)
GymStreak/Presentation/Views/Routines/RoutineSetRowView.swift          Superseded by RoutineSetStepperRow (always-editable rows)
GymStreak/Presentation/Views/Routines/AlternativeSetsInlineEditor.swift Superseded by RoutineSetsEditor (one editor for primary + alternatives)
GymStreak/Presentation/Views/Routines/AlternativeFocusedEditor.swift    Superseded by RoutineAlternativesSection's inline row editor
GymStreak/Presentation/Views/Routines/ExerciseVariantSwitcher.swift     Variant pills replaced by the flat alternatives list
GymStreak/Presentation/Views/Routines/AlternativesBrowseView.swift      Browse sheet replaced by the in-card list
GymStreak/Presentation/Views/Components/RepRangeConfigView.swift        Superseded by RepRangeInlineEditor (chip-triggered)

# v2 bug fixes (2026-07-29)
GymStreak/Presentation/Views/Routines/ExerciseReorder.swift             Hand-rolled onDrag/onDrop reorder — replaced by List + .onMove in sorting mode
```

`SupersetRestTimerConfig.swift` and `RestTimerConfigView.swift` are **kept** — the routine detail no longer uses them, but `ActiveWorkoutView` and `RoutineExerciseDetailView` still do. `WiggleModifier` was deleted with the old edit mode (the drag handle is the sorting affordance now).

### Layer compliance
- **Domain**: `RoutineMetricsService` is pure (no SwiftUI); operates on `@Model` types directly (deliberate, per architecture.md — no DTO layer). `MuscleGroups.color(for:)` lives in **Presentation** (`DomainColorStyling.swift`) so Domain stays SwiftUI-free.
- **Presentation**: Views call ViewModels/repositories only; no `ModelContext`/`FetchDescriptor` in views. `HapticManager.shared` used in Views only (tolerated). New ViewModel work (`refreshLastPerformedDates`, `duplicateRoutine`, `routineUsageCount`) lives in the ViewModels, not Views.
- **Files under folder conventions**; new components in `Views/Components`, new domain service in `Domain/Services`.
- **v2**: `RoutineExerciseCardDisplay`, `WeightFormatting` and `SetSummaryFormatting` are Presentation helpers (Foundation only, no SwiftUI, no `ModelContext`). `RemovedRoutineExerciseSnapshot` sits next to the ViewModel that produces it; its deep-copy/restore mirrors `duplicateRoutine`, which is the established home for model cloning in this codebase (it needs the repository to persist, so it does **not** move to Domain).

### Derived data
- **Last trained per routine** (`RoutinesViewModel.lastPerformedByRoutine`): built from `workoutSessionRepository.fetchCompleted()`, keyed by `session.routine?.id` → most recent `startTime`. Drives the hero selection and card relative dates. Rebuilt on every `fetchRoutines()`.
- **Estimated duration** (`RoutineMetricsService.estimatedDurationMinutes`): ~40s work per set + configured rest between sets + ~60s transition per exercise. Display-only heuristic, nothing stored.
- **Routine usage count** (`ExercisesViewModel.routineUsageCount`): distinct routines referencing an exercise as primary (`routineExercises`) or alternative (`alternativeUses`).
- **Duplicate routine** (`RoutinesViewModel.duplicateRoutine`): deep-copies exercises, sets, rep ranges, alternatives (+ their sets) and **remaps superset ids** so a duplicate never shares a superset id with its source.

### Muscle color palette
`MuscleGroups.color(for:)` maps each muscle group's anatomical **category** to a color (chest→mint, arms→blue, shoulders→purple, back→orange, legs→pink, core→amber, else tint). Categories come from the existing `MuscleGroups.categoryTitleKey(for:)`, so every one of the app's ~19 muscle groups resolves to a stable color, not just the five the mock showed.

## Localization
New keys under `routines.*`, `routine.*`, `exercises.*`, `exercise.detail.*`, `filter.*`, `date.*`, `add_exercise.*`, `action.back`. Both `en.lproj` and `de.lproj` kept in sync. German copy matches the design mock's wording ("Als Nächstes", "Verwendet in", "Ziel %d–%d Wdh.").

**v2 added** `routine.sort`, `routine.sort_hint`, `routine.exercise_removed`, `routine.set_scheme.uniform`, `routine.set_scheme.mixed`, `rest_timer.enable`, `rest_timer.rest_short`, `rest_timer.off`, `rep_range.goal_short`, `rep_range.value`, `rep_range.custom`, `rep_range.no_goal`, `set.weight_compact`, `set.reps_unit`, `set.weight_unit`; and removed `routine.chip.pause`, `routine.chip.goal`, `routine.drag_to_reorder`, `routine.edit_mode_announcement`, `rep_range.clear`, `rep_range.strength`, `rep_range.hypertrophy`, `rep_range.endurance` with the components that used them.

## Known constraints / notes
- **Type-check performance**: `RoutineDetailView.exerciseRows` was originally one expression with three heavily-modified branches and hit the Swift "unable to type-check in reasonable time" error. Fixed by extracting each branch into its own function (`supersetSelectionCard`, `normalExerciseCard`, `exerciseRow`). Keep card branches as separate functions to avoid regressing this. (The former shared `ExerciseListRowChrome` `ViewModifier` was removed with the 2026-07-07 `List`→`LazyVStack` migration — per-child padding replaced it.) The same limit bit again in v2 in an *untouched* file, `CreateRoutineFlow/ConfigureExerciseView.swift`: two inline `Binding(get:set:)` closures over a subscripted `@State` array inside the row body tipped over once the module's file set changed. Fixed by extracting them to `repsBinding(at:)` / `weightBinding(at:)`.
- **Header width (v2)**: the set summary is the card's primary information and must never truncate, so `ExerciseHeaderView`'s meta line is a `ViewThatFits` — the equipment tag is dropped first when the row runs out of width (the v2 header carries an ellipsis menu the design mock does not have, which costs ~30pt).
- **Keyboard dismissal (v2)**: the set rows' typeable values use one shared `@FocusState<Bool>` per screen, passed down as a `FocusState<Bool>.Binding` into `RoutineSetsEditor`, and dismissed by `keyboardDoneBar(isFocused:)`. `ToolbarItemGroup(placement: .keyboard)` was removed from `RoutineDetailView` — it does not render on iOS 26 (see the Exercises-tab notes above for the bug family).
- The redesign is presentation-only; the workout-recording flow (`ActiveWorkoutView`), watch sync, and history are unaffected.

## Watch target
**Unchanged.**
