# Quickstart: Fix Progress Chart Display Issues

**Date**: 2026-04-18
**Feature**: 002-fix-chart-display

## What Changed

Two display fixes to the exercise progress charts:

1. **Y-axis scale fix**: Removed duplicate `AreaMark` data series that caused Swift Charts to compute an incorrect Y-axis domain for the Total Volume tab (and potentially other metrics).
2. **Area fill removal**: Removed the gradient area fill beneath the line on all three chart tabs (Max Weight, Est. 1RM, Total Volume) for cleaner visual presentation.

## Files Modified

| File | Change |
|------|--------|
| `GymStreak/Views/Charts/ExerciseProgressChartView.swift` | Remove `AreaMark` `ForEach` block from `ProgressChartContent` |

## Verification

1. Open the app and navigate to any exercise's progress chart
2. Switch to each metric tab (Max Weight, Est. 1RM, Total Volume)
3. Verify:
   - Y-axis labels match the data point values (no 0-1 range for 400+ kg data)
   - No gradient area fill appears beneath the chart line
   - Tapping data points still shows correct annotations
   - Line and point markers render correctly
