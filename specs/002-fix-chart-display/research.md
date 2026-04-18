# Research: Fix Progress Chart Display Issues

**Date**: 2026-04-18
**Feature**: 002-fix-chart-display

## Finding 1: Y-Axis Scale Mismatch Root Cause

**Decision**: The Y-axis scale bug is caused by dual `ForEach` loops in `ProgressChartContent` creating separate implicit data series for `LineMark`/`PointMark` and `AreaMark`. Swift Charts may interpret these as distinct series with conflicting scales. Additionally, the `formatCompactValue` function formats axis label values — if the chart's automatic axis picks values in thousands (e.g., 0, 500, 1000), the formatting correctly produces "1k kg". However, the visual mismatch between the annotation ("400 kg") and axis labels ("0 kg", "1 kg") strongly suggests the chart's automatic Y-axis domain is being incorrectly computed — likely clamped or normalized due to the duplicate data series from the `AreaMark`.

**Rationale**: Removing the `AreaMark` `ForEach` should resolve both issues simultaneously — the area fill removal (User Story 2) and the Y-axis scaling fix (User Story 1). If the Y-axis issue persists after `AreaMark` removal, the next investigation step is whether `formatCompactValue` produces misleading labels for specific value ranges.

**Alternatives considered**:
- Explicit `.chartYScale(domain:)` — would fix symptoms but not root cause, adds maintenance burden
- Separate chart for AreaMark with shared axis — over-engineered for a fill that's being removed anyway

## Finding 2: Area Fill Evaluation

**Decision**: Remove the `AreaMark` entirely. Area fills under line charts are useful when showing cumulative or stacked data. For single-metric progress tracking (max weight, 1RM, volume), the area fill adds no informational value — the line and point markers already convey the trend and individual values.

**Rationale**: The user confirmed the area fills are not useful. Removing them also simplifies the chart code and may resolve the Y-axis bug.

**Alternatives considered**:
- Reduce opacity further — still adds visual noise without information
- Make area fill toggleable — unnecessary complexity for a decorative element

## Finding 3: Verification Strategy

**Decision**: After removing the `AreaMark`, verify all three metric tabs produce correct Y-axis scales by testing with the app's real data. The `formatCompactValue` function should be reviewed but likely works correctly — the issue is the chart domain, not the label formatting.

**Rationale**: The simplest fix (removing AreaMark) should be tried first before investigating formatting functions.
