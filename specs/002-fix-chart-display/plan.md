# Implementation Plan: Fix Progress Chart Display Issues

**Branch**: `002-fix-chart-display` | **Date**: 2026-04-18 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/002-fix-chart-display/spec.md`

## Summary

Fix two display issues in the exercise progress charts: (1) Y-axis labels showing incorrect scale on the Total Volume tab (showing "0 kg"/"1 kg" while data points show "400 kg"), caused by a duplicate `AreaMark` data series interfering with Swift Charts' automatic Y-axis domain computation; (2) remove gradient area fills from all three chart tabs as they add visual noise without informational value.

## Technical Context

**Language/Version**: Swift 6 with strict concurrency
**Primary Dependencies**: SwiftUI, SwiftUI Charts framework
**Storage**: N/A (display-only fix, no persistence changes)
**Testing**: Manual verification (chart rendering); XCTest if applicable
**Target Platform**: iOS 18.5+
**Project Type**: Mobile app (iOS)
**Performance Goals**: 60 fps chart rendering maintained
**Constraints**: No new dependencies; existing chart interaction behavior preserved
**Scale/Scope**: Single file change (`ExerciseProgressChartView.swift`)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Gate | Status | Notes |
|------|--------|-------|
| I. Code Quality & Architecture | PASS | Change stays within Presentation layer; simplifies code by removing redundant `AreaMark` block |
| II. Testing Standards | PASS | Manual verification sufficient for chart rendering fix; no business logic changed |
| III. User Experience Consistency | PASS | Uses existing `DesignSystem` tokens; improves chart readability |
| IV. Performance Requirements | PASS | Removing `AreaMark` reduces rendering work; no performance regression |
| V. Simplicity & Documentation | PASS | Docs update required for progress-charts feature |

**Post-Phase 1 Re-check**: All gates still PASS. No new patterns, dependencies, or architectural changes introduced.

## Project Structure

### Documentation (this feature)

```text
specs/002-fix-chart-display/
├── plan.md              # This file
├── research.md          # Root cause analysis
├── data-model.md        # No data model changes
├── quickstart.md        # Verification guide
└── spec.md              # Feature specification
```

### Source Code (repository root)

```text
GymStreak/
├── Views/
│   └── Charts/
│       └── ExerciseProgressChartView.swift    # PRIMARY: Remove AreaMark ForEach block
├── Models/
│   └── ExerciseProgressModels.swift           # VERIFY: formatCompactValue correctness
└── ViewModels/
    └── ExerciseProgressViewModel.swift        # NO CHANGES
```

**Structure Decision**: Single-file fix in the existing Charts view directory. No new files, no structural changes.

## Implementation Steps

### Step 1: Remove AreaMark from ProgressChartContent

In `ExerciseProgressChartView.swift`, remove the entire second `ForEach` block (lines ~196-212) that renders the `AreaMark` with gradient fill. This removes the area fill from all three metric tabs and eliminates the duplicate data series that may cause Y-axis scaling issues.

### Step 2: Verify Y-Axis Rendering

After removing the `AreaMark`, build and run the app. Navigate to exercise progress charts and verify:
- Total Volume tab: Y-axis labels match data point values
- Max Weight tab: Y-axis labels are correct
- Est. 1RM tab: Y-axis labels are correct
- Data point tap annotations remain consistent with Y-axis position

### Step 3: Investigate formatCompactValue (if needed)

If Y-axis issues persist after `AreaMark` removal, investigate `formatCompactValue` in `ExerciseProgressModels.swift` for edge cases in the 0..<1 range handling and thousand-scale transitions.

### Step 4: Update Documentation

Update `docs/progress-charts.md` to reflect the removal of area fills from the chart design.

## Complexity Tracking

No constitution violations. No complexity tracking needed.
