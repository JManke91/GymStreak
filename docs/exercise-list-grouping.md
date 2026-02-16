# Exercise List Grouping by Muscle Category

## Overview
The Exercises tab displays exercises grouped by muscle category sections instead of a flat alphabetical list. Categories follow anatomical top-to-bottom order: Shoulders, Chest, Back, Arms, Core, Legs, General.

## How It Works
- Each exercise is categorized by its **primary muscle group** (first element of `muscleGroups` array)
- The primary muscle group is mapped to a parent category via `MuscleGroups.categoryTitleKey(for:)`
- Unknown muscle groups fall back to the "General" category
- Section headers display the localized category name and exercise count
- Exercises within each section retain alphabetical sort order

## Architecture

### Shared Category Definitions (`MuscleGroups.swift`)
- `MuscleGroups.Category` struct: holds `titleKey` (localization key) and `muscleGroupKeys` (English keys)
- `MuscleGroups.categories`: canonical array defining all categories in display order
- `MuscleGroups.categoryTitleKey(for:)`: reverse lookup from muscle group key to category title key
- `MuscleGroups.categorySortOrder(for:)`: returns index in `categories` array for sorting

### Grouping Logic (`ExercisesViewModel.swift`)
- `ExerciseSection` struct: holds `categoryTitleKey` and `[Exercise]`
- `groupedExercises` computed property: groups `exercises` by category, sorts by `categorySortOrder`

### Sectioned List (`ExercisesView.swift`)
- Uses `ForEach(viewModel.groupedExercises)` with `Section` blocks
- Delete uses section-relative offsets via `deleteExercises(in:at:)`
- Uses `.listStyle(.insetGrouped)`

### MuscleGroupPicker Deduplication (`MuscleGroupPicker.swift`)
- `MuscleGroupSelectionSheet` derives its categories from `MuscleGroups.categories` (filtering out "General")
- Eliminates duplicated category data that was previously hardcoded

## Components Involved

| Component | File | Role |
|-----------|------|------|
| `MuscleGroups.Category` | `MuscleGroups.swift` | Category data structure |
| `MuscleGroups.categories` | `MuscleGroups.swift` | Canonical category list |
| `ExerciseSection` | `ExercisesViewModel.swift` | Section model for grouped list |
| `groupedExercises` | `ExercisesViewModel.swift` | Computed grouping property |
| `ExercisesView` | `ExercisesView.swift` | Sectioned list UI |
| `MuscleGroupSelectionSheet` | `MuscleGroupPicker.swift` | Uses shared categories |

## Targets
- **iOS**: Full sectioned exercise list in Exercises tab
- **watchOS**: Not affected (watch does not have an exercise library tab)

## Localization
Category title keys are localized in both `en.lproj` and `de.lproj` Localizable.strings files.
