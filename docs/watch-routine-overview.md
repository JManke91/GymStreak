# Watch Routine Overview

## Feature

The `RoutineDetailView` on Apple Watch shows a pre-workout overview of a routine: exercise count, total sets, and an exercise list. Each exercise card displays the name, set count, muscle group, and — since this enhancement — a compact planned-sets summary line.

## What Changed

`ExercisePreviewRow` shows a third text line with planned set details. It uses a **single consistent format** — `<sets> × <reps> @ <weight>` — for every exercise:

- **Uniform sets** (same reps + weight): `3 × 10 @ 80 kg`
- **Varying weight only**: `3 × 10 @ 60–80 kg`
- **Varying reps only**: `3 × 8–12 @ 80 kg`
- **Both vary**: `3 × 8–12 @ 60–80 kg`
- **Bodyweight** (weight == 0): `3 × 10` (weight part omitted)

Ranges are always rendered **ascending (min–max)** and the `@` separator is used in every case, so the line reads the same way across all exercises.

## Architecture

### `WatchExercise.setsSummary` (WatchModels.swift)

A computed property on `WatchExercise` that derives the display string from `sets: [WatchSet]`. Uses `Measurement<UnitMass>.formatted(.measurement(width: .abbreviated, usage: .general))` for locale-aware kg/lbs conversion — no user preference required; Foundation auto-converts based on the device locale.

### `ExercisePreviewRow` (RoutineDetailView.swift)

Adds a conditional third `Text` row below the existing "N sets · MuscleGroup" subtitle. Uses `.caption2` font and `.tertiary` foreground to visually rank below the primary and secondary labels.

## Design Decisions

- **Inline text, no expansion**: `DisclosureGroup` is not available on watchOS; manual `@State` toggle was rejected because the overview is a quick pre-flight check, not a browsing screen. A single summary line per exercise keeps the list scannable.
- **Consistent `N × reps @ weight` format**: An earlier version switched separators (`@` vs `·`) and the "reps" label based on whether reps/weights were uniform, producing visually inconsistent rows across exercises. It also used first→last set order, so descending pyramids rendered as backwards ranges like `5–3` that read as typos. The format is now uniform: always `sets × reps @ weight`, always ascending min–max ranges.
- **Tertiary foreground**: Keeps visual hierarchy: name (primary) → count + muscle (secondary) → set plan (tertiary).
- **Bodyweight guard**: `weight == 0` is treated as bodyweight and the weight part is omitted to avoid `"3 × 10 @ 0 kg"`.

## Files

| File | Change |
|------|--------|
| `GymStreakWatch Watch App/Models/WatchModels.swift` | Added `setsSummary` computed property to `WatchExercise` |
| `GymStreakWatch Watch App/Views/RoutineDetailView.swift` | Added summary line in `ExercisePreviewRow` |
