# Superset Feature

## Overview

Supersets allow users to group 2+ exercises together so they alternate sets during a workout. Instead of completing all sets of exercise A before moving to B, supersets interleave them: A1 → B1 → A2 → B2 → A3 → B3. Rest timers only trigger after completing a full round (all exercises at the same set level).

This feature is fully implemented on both iOS and watchOS with bidirectional data sync.

---

## Data Model

### Core Fields

Two fields on `RoutineExercise` power the entire feature:

| Field | Type | Description |
|-------|------|-------------|
| `supersetId` | `UUID?` | Shared UUID grouping exercises together. `nil` = standalone exercise |
| `supersetOrder` | `Int` | Position within the superset (0-indexed) |

These fields are mirrored on:
- **`WorkoutExercise`** - Denormalized copy for workout history (preserves structure even if routine changes later)
- **`WatchExercise`** (Codable) - For iOS → Watch sync
- **`ActiveWorkoutExercise`** - Watch app's in-memory workout state
- **`CompletedWatchExercise`** - For Watch → iOS sync after workout completion

All fields use iCloud-compatible defaults (`nil`, `0`) requiring no schema migrations.

### Computed Properties

| Property | On | Purpose |
|----------|-------|---------|
| `isInSuperset: Bool` | `RoutineExercise`, `WorkoutExercise`, `ActiveWorkoutExercise` | Returns `supersetId != nil` |
| `exercisesGroupedBySupersets: [[RoutineExercise]]` | `Routine` | Groups exercises by `supersetId`. Standalone = `[[ex]]`, Superset = `[[ex1, ex2, ex3]]` sorted by `supersetOrder` |
| `exercisesGroupedBySupersets: [[WorkoutExercise]]` | `WorkoutSession` | Same grouping logic for active workouts |

**Files:**
- `GymStreak/Models.swift` - SwiftData models, `Routine.exercisesGroupedBySupersets` (~line 32), `WorkoutSession.exercisesGroupedBySupersets` (~line 212)
- `GymStreak/WatchModels.swift` - iOS-side Codable watch models
- `GymStreakWatch Watch App/Models/WatchModels.swift` - Watch-side models

---

## CRUD Operations (iOS)

All superset management is in `RoutinesViewModel` (~lines 155-230):

| Operation | Method | Behavior |
|-----------|--------|----------|
| **Create** | `createSuperset(from:in:)` | Assigns new shared `supersetId` + sequential `supersetOrder` to 2+ exercises |
| **Add** | `addExerciseToSuperset(_:supersetId:in:)` | Appends exercise with `supersetOrder = maxOrder + 1` |
| **Remove** | `removeExerciseFromSuperset(_:in:)` | Clears fields. Auto-dissolves if only 1 exercise remains |
| **Dissolve** | `dissolveSuperset(_:in:)` | Clears `supersetId`/`supersetOrder` on all exercises in the group |
| **Reorder** | `reorderSuperset(_:in:)` | Reassigns sequential `supersetOrder` values |

**Auto-dissolution**: Removing an exercise from a 2-exercise superset automatically dissolves it (prevents single-exercise supersets).

**File:** `GymStreak/RoutinesViewModel.swift`

---

## Workout Execution

### Interleaved Navigation Pattern

```
Standard exercise:    A1 → A2 → A3
Superset [A, B]:      A1 → B1 → [REST] → A2 → B2 → [REST] → A3 → B3
Superset [A, B, C]:   A1 → B1 → C1 → [REST] → A2 → B2 → C2 → [REST] → ...
```

Handles uneven set counts gracefully (e.g., A has 3 sets, B has 4 → round 4 only includes B).

### Key Navigation Functions

**iOS** (`GymStreak/WorkoutViewModel.swift` ~lines 792-958):

| Function | Purpose |
|----------|---------|
| `findNextIncompleteSet()` | Global navigation using `exercisesGroupedBySupersets`. For supersets, iterates by set level across all exercises |
| `findNextIncompleteSetForSuperset(after:in:)` | Implements the interleaving pattern within a superset group |
| `isEndOfSupersetRound(completedSet:in:)` | Returns `true` when ALL exercises at a set level are complete |
| `supersetRoundRestTime(for:in:)` | Gets rest time from **last exercise's** set at that level |

**watchOS** (`WatchWorkoutViewModel.swift` ~lines 460-718) - mirrors identical logic:

| Function | Purpose |
|----------|---------|
| `findNextIncompleteSet()` | Same interleaving logic |
| `findNextIncompleteSetInSuperset(afterSetIndex:inExerciseIndex:)` | Superset-specific navigation |
| `isEndOfSupersetRound(exerciseIndex:setIndex:)` | Round completion detection |
| `supersetRoundRestTime(exerciseIndex:setIndex:)` | Rest time for completed round |
| `advanceToNextSetAfterCompletion(fromExerciseIndex:setIndex:)` | Post-completion navigation |

### Rest Timer Behavior

| Scenario | When rest starts |
|----------|-----------------|
| **Standalone exercise** | After each set |
| **Superset** | Only after completing a full round (all exercises at same set level) |

Rest time is stored on the **last exercise's sets** in the superset. Rationale: rest comes after completing all exercises in the round.

### Set Completion Flow

1. Mark set complete
2. Check `exercise.isInSuperset`
3. **If superset**: Check `isEndOfSupersetRound()` → start rest timer only if round complete → navigate to next set via interleaving
4. **If standalone**: Start rest timer → navigate to next set sequentially

**iOS:** `GymStreak/WorkoutViewModel.swift` - `completeSet(workoutExercise:set:)` (~lines 470-526)
**Watch:** `GymStreakWatch Watch App/ViewModels/WatchWorkoutViewModel.swift` - `applyToggleSetCompletion()` (~lines 280-313)

---

## iOS UI Components

### Multiple Supersets Per Routine

The app supports **multiple independent supersets** within a single routine. Each superset is identified by a unique `supersetId` UUID and gets a computed letter label (A, B, C...) assigned at display time by `SupersetLabelProvider`.

### Superset Label Provider

**File:** `GymStreak/Helpers/SupersetLabelProvider.swift`

- `SupersetLabelProvider.labels(for:)` - Computes `[UUID: String]` mapping from supersetId to letter (A, B, C...) based on exercise order
- `SupersetLabelProvider.color(for:)` - Returns a unique color per letter: green (A), indigo (B), orange (C), blue (D), pink (E), cycling
- `SupersetGroupable` protocol - Shared by `RoutineExercise` and `WorkoutExercise` for generic label computation

Labels are computed at render time, not stored. If superset A is dissolved, B automatically becomes A.

### Superset Visual Indicators

| Component | File | Purpose |
|-----------|------|---------|
| `SupersetBadge` | `GymStreak/Views/Components/SupersetBadge.swift` | Position/total badge (e.g., "1/2", "2/3") with per-group color |
| `SupersetIndicatorBadge` | Same file | Header badge: "Superset A (3)" with link icon and per-group color |
| `SupersetLineIndicator` | `GymStreak/Views/Components/SupersetLineIndicator.swift` | Vertical connecting line with per-group color. Positions: `.first`, `.middle`, `.last`, `.only` |
| `SupersetGroupView` | `GymStreak/Views/Components/SupersetGroupView.swift` | Container for grouped exercises with connecting line and per-group color |
| `SupersetRestTimerConfig` | `GymStreak/Views/Components/SupersetRestTimerConfig.swift` | Single rest timer config for entire superset. Shows only on first exercise |

### Routine Detail - Superset Management

**File:** `GymStreak/RoutineDetailView.swift`

**Context Menu** (per-exercise, supports multiple supersets):

For exercises **in a superset**:
- "Remove from Superset A" → `viewModel.removeExerciseFromSuperset()`
- "Dissolve Superset A" → `viewModel.dissolveSuperset()`

For **standalone exercises** (not in any superset):
- "Create Superset With..." submenu → lists other standalone exercises → `viewModel.createSuperset(from:in:)`
- "Add to Superset A" / "Add to Superset B" → `viewModel.addExerciseToSuperset(_:supersetId:in:)`

For **deleting**:
- "Delete Exercise" → confirms and removes

**Visual styling:**
- Each superset group gets a unique color from `SupersetLabelProvider`
- Superset exercises: `groupColor.opacity(0.08)` background
- 16pt indicator area for `SupersetLineIndicator` (ensures vertical alignment)
- Badges show position/total: "1/2", "2/2" (user-friendly format)

### Active Workout - Superset Display

**File:** `GymStreak/ActiveWorkoutView.swift`

| Component | Purpose |
|-----------|---------|
| `SupersetWorkoutGroupView` | Groups superset exercises in a card with header "Superset A (3)", per-group colored connecting line, rest time indicator |
| `ExerciseCard` | Shows `SupersetBadge` (e.g., "1/3") with per-group color when part of superset. Hides individual rest timer config. Highlighted border when current exercise |

Workout labels are computed from `WorkoutSession.workoutExercisesList` using `SupersetLabelProvider.labels(for:)`.

### Rest Timer Config

- **Standalone**: Regular `RestTimerConfigView` per exercise
- **Superset**: `SupersetRestTimerConfig` shown only on **first exercise** in the group
  - Updates rest time on **last exercise's sets**
  - Includes explanation: "Rest starts after completing all exercises in each round"

**Helper functions in RoutineDetailView:**
- `supersetLabels` - Computed `[UUID: String]` from `SupersetLabelProvider`
- `supersetColor(for:)` / `supersetLetter(for:)` - Per-exercise color/letter accessors
- `supersetRestTime(for:)` - Gets rest time from last exercise
- `updateSupersetRestTime(for:restTime:)` - Updates all sets of last exercise
- `supersetInfo(for:)` - Returns `(position: Int, total: Int)` (1-indexed)
- `isFirstInSuperset(_:)` / `lastExerciseInSuperset(for:)`
- `supersetLinePosition(for:)` - Returns visual indicator position

---

## watchOS Implementation

### Routine Preview

**File:** `GymStreakWatch Watch App/Views/RoutineDetailView.swift`

- Groups exercises using `exerciseGroups` computed property (by `supersetId`)
- Superset display:
  - Header: "Superset (N)" with link icon
  - Tinted background: `tint.opacity(0.1)`
  - Border: `tint.opacity(0.3)`
  - Dividers between exercises in the same group
- `ExercisePreviewRow` shows superset position badge when `showSupersetBadge: true`

### Active Workout

**File:** `GymStreakWatch Watch App/Views/ActiveWorkoutView.swift`

- TabView with 3 tabs: Exercises, Metrics, Controls
- Set editor (`FullScreenSetEditorView`) displays current exercise name, supports superset switching via ViewModel
- Rest timer overlay (full-screen or minimized)

**File:** `GymStreakWatch Watch App/Views/ExerciseListView.swift`

- `WatchSupersetBadge` (~lines 337-361): Link icon + position number
- Badge colors: `textOnTint` (black) on `tint` (green) background
- Row background: `Color.accentColor.opacity(0.1)` for superset exercises

**File:** `GymStreakWatch Watch App/Views/CompactActionBar.swift`

- Complete button triggers `toggleSetCompletion()`
- Navigation (prev/next) delegates to ViewModel's superset-aware logic
- Shows exercise name to indicate which superset exercise is active

### Design System

**File:** `GymStreakWatch Watch App/OnyxWatchDesignSystem.swift`

- `OnyxWatch.Colors.tint` - Green color for superset indicators
- `OnyxWatch.Colors.textOnTint` - Black text for contrast on tint backgrounds

---

## Data Sync (iOS ↔ watchOS)

### iOS → Watch

1. `Routine.toWatchRoutine()` converts SwiftData models to Codable `WatchRoutine`
2. Preserves `supersetId` and `supersetOrder` on each `WatchExercise`
3. Sent via `WatchConnectivityManager.updateApplicationContext()` (background) or `sendMessage()` (foreground)

### Watch → iOS

1. Watch completes workout, creates `CompletedWatchWorkout` with superset metadata on each `CompletedWatchExercise`
2. Sent via `transferUserInfo()` (guaranteed delivery)
3. iOS receives via `didReceiveUserInfo`, posts `watchWorkoutCompleted` notification
4. `RoutinesViewModel` processes completed workout, creates `WorkoutSession` with denormalized superset data

**Files:**
- `GymStreak/WatchConnectivityManager.swift` - iOS side
- `GymStreakWatch Watch App/Managers/WatchConnectivityManager.swift` - Watch side

---

## First-Time UX

| Hint | Storage Key | Behavior |
|------|-------------|----------|
| Reorder hint | `hasSeenReorderHint` | Shows in edit mode, auto-dismisses after 4-5s |

Stored in `@AppStorage` (UserDefaults).

---

## Localization

Key strings in `GymStreak/Resources/en.lproj/Localizable.strings`:

- `superset.rest_timer.explanation` - "Rest starts after completing all exercises in each round"
- `superset.remove_from` / `superset.remove_from_named` - Remove from superset actions
- `superset.dissolve` / `superset.dissolve_named` - Dissolve superset actions
- `superset.create_with` - "Create Superset With..." context menu label
- `superset.add_to` - "Add to Superset %@" context menu label

---

## All Files Reference

### Data Models
| File | Contains |
|------|----------|
| `GymStreak/Models.swift` | `RoutineExercise.supersetId/supersetOrder`, `WorkoutExercise` mirrors, grouping computed properties |
| `GymStreak/WatchModels.swift` | `WatchExercise`, `CompletedWatchExercise` with superset fields |
| `GymStreakWatch Watch App/Models/WatchModels.swift` | `ActiveWorkoutExercise.isInSuperset`, watch-side models |

### Helpers
| File | Contains |
|------|----------|
| `GymStreak/Helpers/SupersetLabelProvider.swift` | `SupersetGroupable` protocol, letter label computation (A/B/C), per-group color assignment |

### ViewModels
| File | Contains |
|------|----------|
| `GymStreak/RoutinesViewModel.swift` | Superset CRUD operations (~lines 155-230) |
| `GymStreak/WorkoutViewModel.swift` | iOS workout superset navigation & rest timers (~lines 470-958) |
| `GymStreakWatch Watch App/ViewModels/WatchWorkoutViewModel.swift` | Watch workout superset logic (~lines 280-718) |

### iOS UI Components
| File | Contains |
|------|----------|
| `GymStreak/Views/Components/SupersetBadge.swift` | `SupersetBadge` (position/total+color), `SupersetIndicatorBadge` (letter+count+color) |
| `GymStreak/Views/Components/SupersetLineIndicator.swift` | Vertical connecting line with position variants and per-group color |
| `GymStreak/Views/Components/SupersetGroupView.swift` | Grouped container with connecting line, letter, and per-group color |
| `GymStreak/Views/Components/SupersetRestTimerConfig.swift` | Rest timer config wrapper for supersets |

### iOS Views
| File | Contains |
|------|----------|
| `GymStreak/RoutineDetailView.swift` | Context menu-based superset management, per-group visual indicators, `ExerciseHeaderView` with position/total badges |
| `GymStreak/ActiveWorkoutView.swift` | `SupersetWorkoutGroupView` with letter/color, `ExerciseCard` with position/total badges |

### watchOS Views
| File | Contains |
|------|----------|
| `GymStreakWatch Watch App/Views/RoutineDetailView.swift` | Superset group preview with badges |
| `GymStreakWatch Watch App/Views/ExerciseListView.swift` | `WatchSupersetBadge`, exercise list with superset tinting |
| `GymStreakWatch Watch App/Views/ActiveWorkoutView.swift` | Main workout flow |
| `GymStreakWatch Watch App/Views/FullScreenSetEditorView.swift` | Set editor with superset context |
| `GymStreakWatch Watch App/Views/CompactActionBar.swift` | Set completion and navigation controls |

### Sync
| File | Contains |
|------|----------|
| `GymStreak/WatchConnectivityManager.swift` | iOS-side sync, receives completed watch workouts |
| `GymStreakWatch Watch App/Managers/WatchConnectivityManager.swift` | Watch-side sync, sends completed workouts |
