# Quickstart: Improve Progress Charts UX

**Branch**: `001-improve-progress-charts` | **Date**: 2026-04-18

## What This Feature Does

Improves the exercise progress charts in the History tab by:
1. Renaming unclear metric labels ("Volume" → "Total Volume") and adding info popovers explaining each metric
2. Adding units (kg) to chart Y-axis and adaptive date formatting on X-axis
3. Enabling tap-to-inspect on data points with floating annotation tooltips

## Files to Modify

### Models (Domain Layer)
- `GymStreak/Models/ExerciseProgressModels.swift` — Add `localizedDescription`, `axisLabel`, date format properties to `ProgressMetric` and `ChartTimeframe` enums. Add `SelectedDataPoint` struct.

### ViewModels (Presentation Layer)
- `GymStreak/ViewModels/ExerciseProgressViewModel.swift` — Add `@Published var selectedDataPoint: SelectedDataPoint?`, selection/dismissal methods, and formatted value helpers.

### Views (Presentation Layer)
- `GymStreak/Views/Charts/ExerciseProgressChartView.swift` — Update axis configuration, add metric info button, integrate chart overlay for tap interaction and annotation rendering.

### New Views (extract to keep under 300 lines)
- `GymStreak/Views/Charts/ChartDataPointAnnotation.swift` — **NEW** — Floating annotation view for selected data point tooltip.
- `GymStreak/Views/Charts/MetricInfoPopover.swift` — **NEW** — Info popover view showing metric description.

### Localization
- `GymStreak/Resources/en.lproj/Localizable.strings` — Add metric description keys, update volume label
- `GymStreak/Resources/de.lproj/Localizable.strings` — Same changes in German

### Documentation
- `docs/progress-charts.md` — **NEW or UPDATE** — Document the progress feature per constitution requirements

## Key Technical Decisions

1. **chartOverlay + ChartProxy** for tap-to-data-point mapping (Apple's recommended pattern)
2. **chartAnnotation on RuleMark** for floating tooltip (native chart anchoring)
3. **Extract annotation & info popover** into separate files (ExerciseProgressChartView already at 311 lines)
4. **Volume unit stays "kg"** — consistent with fitness industry convention; info popover clarifies calculation

## Build & Verify

```bash
# Open in Xcode
open GymStreak.xcodeproj
# Build: Cmd+R
# Clean: Cmd+Shift+K
```

Verify by:
1. Navigate to History tab → Progress mode → select any exercise
2. Check metric picker shows "Max Weight", "Est. 1RM", "Total Volume"
3. Tap ⓘ icon → popover explains the metric
4. Check Y-axis shows "kg" unit, X-axis shows appropriate date granularity
5. Tap a data point → floating annotation shows value + date
6. Tap elsewhere → annotation dismisses
7. Switch to German → all labels localized correctly
