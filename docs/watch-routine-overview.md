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

## Start Button Icon Alignment

The bottom "Start Workout" button (`startButton`, pinned via `safeAreaInset`) is narrower
than the routine-list quick-start button, so in longer locales its title wraps to two
lines — German "Workout starten" does this on a 40/41 mm case. With SwiftUI's
`DefaultLabelStyle` the `play.fill` glyph is pinned to the **first** text line, leaving it
visibly high against a two-line title. The button now applies
`.labelStyle(.centeredIcon)` (`CenteredIconLabelStyle`, defined in
`OnyxWatchDesignSystem.swift`).

### Research findings

- SwiftUI documents `.titleAndIcon` only as "a system-standard layout". The vertical
  alignment it uses between icon and title is **not documented**; first-line pinning is an
  observed behavior, not a published contract.
- There is **no** first-party alignment knob: none of `.automatic`, `.iconOnly`,
  `.titleAndIcon`, `.titleOnly` take an alignment parameter, and `Label.init(title:icon:)`
  has no such argument. A custom type conforming to `LabelStyle` and composing
  `configuration.icon` / `configuration.title` is the only supported mechanism, and is the
  pattern Apple's own `Label` documentation demonstrates.
- `VerticalAlignment.firstTextBaseline` is **not** a fix — it explicitly anchors to the
  top-most text baseline, i.e. it reproduces exactly the bug being fixed. `.center` is the
  only alignment that centers the icon against the whole multi-line block.
- The system's icon sizing and icon/title gap are internal to `DefaultLabelStyle` and are
  **lost** when the style is replaced. Apple publishes no constant for either.

### Why `imageScale(.large)` and `spacing: 9`

A bare `HStack { configuration.icon; configuration.title }` is not a neutral
re-implementation: measured against the unstyled label on a 40 mm case at
`.watchSubheadline`, it rendered the glyph at 20×23 px instead of 27×30 px and closed the
icon→title ink gap from 21 px to 11 px — a visible regression on the single-line watches
this fix must not disturb. `.imageScale(.large)` restores the glyph to 27×30 px exactly;
`spacing: 9` restores the 21 px gap exactly.

`spacing` is declared `@ScaledMetric(relativeTo: .body)`, because `imageScale(.large)` grows
the glyph with the text size while a fixed point value would not — matching only at the
default size and drifting at every other. This forces one structural detail: a `LabelStyle`
is **not** a `View`, so `DynamicProperty` wrappers declared on the style struct are never
resolved. The `HStack` therefore lives in a nested `private struct Content: View` that
`makeBody` returns; a `@ScaledMetric` on `CenteredIconLabelStyle` itself would silently
never update.

Verified by A/B screenshot on `Paired Apple Watch SE 3 40mm` (watchOS 26.5), German:

| Case | Icon center y | Title center y | Icon size | Ink gap |
|------|---------------|----------------|-----------|---------|
| Single line, `DefaultLabelStyle` (baseline) | 309.5 | 308.0 | 27×30 | 21 px |
| Single line, `CenteredIconLabelStyle` | 309.5 | 309.0 | 27×30 | 21 px |
| Two lines, `CenteredIconLabelStyle` | 344.5 | 343.0 | 29×32 | 24 px |

(Measured again after the `@ScaledMetric` refactor: both rows unchanged to the pixel, as
expected — the scaled value resolves to its 9 pt base at the default text size.)

The single-line rows match within sub-pixel rounding, so bigger watches are unaffected;
the two-line row shows the glyph centered against the full title block (1.5 px apart).
The two-line icon is slightly larger because `startButton` does not set
`.watchSubheadline` and inherits the default body font — pre-existing, unrelated.

### Deliberately not applied to the routine list

`RoutineListView.quickStartButton` still uses the default label style. It spans the full
list-row width, so its title does not wrap, and the A/B above confirms the custom style
would be a visual no-op there. Applying it was measured and then reverted to keep the
change scoped; it is a safe one-line addition if a future locale wraps that button too.

## Files

| File | Change |
|------|--------|
| `GymStreakWatch Watch App/Models/WatchModels.swift` | Added `setsSummary` computed property to `WatchExercise` |
| `GymStreakWatch Watch App/Views/RoutineDetailView.swift` | Added summary line in `ExercisePreviewRow`; `startButton` applies `.labelStyle(.centeredIcon)` |
| `GymStreakWatch Watch App/OnyxWatchDesignSystem.swift` | Added `CenteredIconLabelStyle` + `LabelStyle.centeredIcon` |
