# Routinen & Übungen Redesign

## What it is
A full visual redesign of the **Routines** (Routinen) and **Exercises** (Übungen) tabs to match the editorial dark style already shipped for the History/Verlauf tab (see [history-redesign.md](./history-redesign.md)). All existing functionality is preserved — this is a presentation-layer redesign, not a behavioral change. No SwiftData schema changes.

Target: **iOS app only** (`GymStreak`). The watch target is untouched.

Source of truth for the visual spec: the Claude Design project *"Routinen & Übungen Redesign.html"* (imported 2026-07-03). The design's React/JSX mock (`gs-*.jsx`) informed the SwiftUI implementation; colors, spacing, and copy were adapted to the app's real data model and existing DesignSystem.

## Scope decisions (confirmed with the user)
- **Both tabs** redesigned (Routinen + Übungen). History was already done.
- **Native `TabView` kept** — the design's floating pill tab bar was *not* adopted, to avoid app-wide regressions and keyboard-avoidance loss. Only screen content changed.
- **All existing features kept and restyled** — supersets, rep ranges + progressive overload, per-set reorder, alternative exercises, multi muscle groups. The mock's simpler data model did not drive feature removal.
- **"Up Next" hero card included** — the least-recently-trained routine is promoted with a full-width start button.

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
- **Container: `ScrollView` + `LazyVStack`, not `List` (2026-07-07).** Originally `List(.plain)`. `List` snaps intra-row height changes (Apple-DTS-confirmed iOS-18 limitation), so expanding a card/set looked like a re-render, not a growth. Moved to `LazyVStack` (per-child padding replaces `listRowInsets`; cards use `.frame(maxWidth:.infinity)` to stretch) where height interpolates. Card expansion now uses `.transition(.opacity.combined(with:.move(edge:.top)))` inside `withAnimation(spring)`, clipped by the card's `.clipShape`. Drag-to-reorder (previously `List.onMove`) is reimplemented in `ExerciseReorder.swift` (`.onDrag`/`.onDrop` + `ExerciseDropDelegate`, live reorder with system auto-scroll), applied only to edit-mode cards; `persistReorder` reassigns `order` and saves.
- **Top bar**: back chevron, Bearbeiten/Fertig toggle, ellipsis menu (Rename via alert, Duplicate, Delete).
- **Title block**: routine name, horizontally-scrolling muscle chips + meta (`routines.card_meta`).
- **Exercise card** (`normalExerciseCard`): `ExerciseHeaderView` (avatar, name, set summary, equipment tag, alternatives affordance, actions menu, superset badge) + always-visible info chips (Pause / Ziel / Alternativen via `MetaChipView`) + expandable body. The expanded body shows **one variant at a time** via `ExerciseVariantSwitcher` pills (primary + alternatives); the focused variant's editor is either `primarySetContent` or `AlternativeFocusedEditor` (details in `alternative-exercises.md`). The **Alternativen chip is tappable** (2026-07-07): it opens `AlternativesBrowseView`, a one-tap browse sheet that expands the card focused on the chosen alternative; the detail view is wrapped in a `ScrollViewReader` with each card carrying `.id(routineExercise.id)` so the jump can scroll the target card into view. Expansion shows either the normal set list (`RoutineSetRowView`) + the always-inline `AlternativeInlineSection`, or the set-reorder editor. The separate "alternatives edit mode" was removed 2026-07-07 (see `alternative-exercises.md`).
- **Preserved subsystems** (unchanged logic, restyled containers): rest-timer config, rep-range config, progressive-overload banner, superset link buttons / edit mode / context menu, per-set expand-to-edit with "apply to all" banners, drag-to-reorder with first-run hint.
- **Sticky CTA**: gradient-backed "Workout starten" via `safeAreaInset(edge: .bottom)`; replaced by the superset-edit toolbar when a superset edit is active.

### Exercises tab (`ExercisesView`)
- Same dark canvas + hidden nav bar. Header (`exercises.header_meta`), `RedesignSearchBar`, two horizontal filter-pill rows (muscle **category** + equipment), and exercises grouped by muscle category with colored-dot section headers.
- `ExerciseLibraryRowView`: avatar, name, equipment tag, "in N routines" count (`ExercisesViewModel.routineUsageCount`), muscle chip. `NavigationLink(value: exercise.id)` → `ExerciseDetailView`.
- DEBUG-only "delete all" and the standard add/delete confirmation alerts are retained.

### Exercise detail (`ExerciseDetailView`)
- Custom top bar with ellipsis menu (Edit / Delete). Hero (large avatar + muscle-colored uppercase label + name), info card (muscle chips + equipment), and a **"Verwendet in"** list built from `exercise.routineExercises` (primary) + `exercise.alternativeUses` (alternative), showing a per-routine set summary and an "Alternative" chip.
- Editing now reuses `AddExerciseView` (via `exerciseToEdit:`); the old inline-editing `ExerciseDetailView` form and the separate `EditExerciseView` were removed.

### Add / edit exercise (`AddExerciseView`)
- One component now handles both create and edit (`exerciseToEdit:` optional). Sheet header (Abbrechen / Speichern) or nav-toolbar save depending on `presentationMode`.
- Name card, muscle-group pills grouped by category (multi-select, `FlowLayout` wrapping), equipment tiles, and a **live preview row** of the resulting library entry.

### Exercise picker (`AddExerciseToRoutineView`)
- Restyled to the dark canvas: `RedesignSearchBar`, "Verfügbar" section (tap → `ConfigureExerciseSetsView`, unchanged), "Bereits in Routine" section (dimmed + check), dashed "Neue Übung erstellen" button. `ConfigureExerciseSetsView` (set/alternative configuration) was left functionally unchanged.

## Architecture

### New files
```
GymStreak/Domain/Services/RoutineMetricsService.swift            Pure metrics: totalSets, estimatedDurationMinutes, primaryMuscleGroups, uniformSetScheme
GymStreak/Presentation/Views/Components/ExerciseVisuals.swift    ExerciseAvatarView, MuscleChipView, EquipmentTagView, MetaChipView
GymStreak/Presentation/Views/Components/RedesignControls.swift   RedesignSearchBar, FilterPillButton, DashedCreateButton, FlowLayout
GymStreak/Presentation/Views/Routines/RoutineCardView.swift      Hero + regular routine card
GymStreak/Presentation/Views/Routines/RoutineDetailComponents.swift  ExerciseHeaderView, RoutineSetRowView, WiggleModifier (extracted)
docs/routines-exercises-redesign.md
```

### Modified files
```
RoutinesView.swift            Rewritten (hero + card list)
RoutineDetailView.swift       Rewritten body; superset/rep-range/alternatives logic preserved
ExercisesView.swift           Rewritten (filters + grouped library)
ExerciseDetailView.swift      Rewritten (hero + info card + used-in); edits via AddExerciseView
AddExerciseView.swift         Rewritten; now also handles editing (exerciseToEdit:)
AddExerciseToRoutineView.swift Picker section restyled; ConfigureExerciseSetsView unchanged
RoutinesViewModel.swift       + lastPerformedByRoutine, upNextRoutine, refreshLastPerformedDates, duplicateRoutine
ExercisesViewModel.swift      + routineUsageCount(for:)
DomainColorStyling.swift      + MuscleGroups.color(for:) — muscle category → color mapping (Presentation)
TimeFormatting.swift          + lastTrainedLabel(for:) relative date
Resources/{en,de}.lproj/Localizable.strings  New keys (see below)
```

### Deleted files
```
GymStreak/Presentation/Views/Exercises/EditExerciseView.swift   Superseded by AddExerciseView editing mode
```

### Layer compliance
- **Domain**: `RoutineMetricsService` is pure (no SwiftUI); operates on `@Model` types directly (deliberate, per architecture.md — no DTO layer). `MuscleGroups.color(for:)` lives in **Presentation** (`DomainColorStyling.swift`) so Domain stays SwiftUI-free.
- **Presentation**: Views call ViewModels/repositories only; no `ModelContext`/`FetchDescriptor` in views. `HapticManager.shared` used in Views only (tolerated). New ViewModel work (`refreshLastPerformedDates`, `duplicateRoutine`, `routineUsageCount`) lives in the ViewModels, not Views.
- **Files under folder conventions**; new components in `Views/Components`, new domain service in `Domain/Services`.

### Derived data
- **Last trained per routine** (`RoutinesViewModel.lastPerformedByRoutine`): built from `workoutSessionRepository.fetchCompleted()`, keyed by `session.routine?.id` → most recent `startTime`. Drives the hero selection and card relative dates. Rebuilt on every `fetchRoutines()`.
- **Estimated duration** (`RoutineMetricsService.estimatedDurationMinutes`): ~40s work per set + configured rest between sets + ~60s transition per exercise. Display-only heuristic, nothing stored.
- **Routine usage count** (`ExercisesViewModel.routineUsageCount`): distinct routines referencing an exercise as primary (`routineExercises`) or alternative (`alternativeUses`).
- **Duplicate routine** (`RoutinesViewModel.duplicateRoutine`): deep-copies exercises, sets, rep ranges, alternatives (+ their sets) and **remaps superset ids** so a duplicate never shares a superset id with its source.

### Muscle color palette
`MuscleGroups.color(for:)` maps each muscle group's anatomical **category** to a color (chest→mint, arms→blue, shoulders→purple, back→orange, legs→pink, core→amber, else tint). Categories come from the existing `MuscleGroups.categoryTitleKey(for:)`, so every one of the app's ~19 muscle groups resolves to a stable color, not just the five the mock showed.

## Localization
New keys under `routines.*`, `routine.*`, `exercises.*`, `exercise.detail.*`, `filter.*`, `date.*`, `add_exercise.*`, `action.back`. Both `en.lproj` and `de.lproj` kept in sync. German copy matches the design mock's wording ("Als Nächstes", "Verwendet in", "Ziel %d–%d Wdh.").

## Known constraints / notes
- **Type-check performance**: `RoutineDetailView.exerciseRows` was originally one expression with three heavily-modified branches and hit the Swift "unable to type-check in reasonable time" error. Fixed by extracting each branch into its own function (`supersetSelectionCard`, `editExerciseCard`, `exerciseRow`). Keep card branches as separate functions to avoid regressing this. (The former shared `ExerciseListRowChrome` `ViewModifier` was removed with the 2026-07-07 `List`→`LazyVStack` migration — per-child padding replaced it.)
- The redesign is presentation-only; the workout-recording flow (`ActiveWorkoutView`), watch sync, and history are unaffected.

## Watch target
**Unchanged.**
