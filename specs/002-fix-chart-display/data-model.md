# Data Model: Fix Progress Chart Display Issues

**Date**: 2026-04-18
**Feature**: 002-fix-chart-display

## No Data Model Changes

This feature is a display-layer bug fix. No data model entities, attributes, or relationships are modified.

### Affected Display Components (no schema changes)

- **ExerciseProgressDataPoint**: Existing struct — no changes to fields. The `value(for:)` method continues to return the correct raw value for each metric.
- **SelectedDataPoint**: Existing struct — no changes. Display formatting via `formatCompactValue` is unaffected.
- **ProgressMetric**: Existing enum — no changes to cases or unit definitions.
