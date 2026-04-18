# Implementation Plan: Improve Progress Charts UX

**Branch**: `001-improve-progress-charts` | **Date**: 2026-04-18 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-improve-progress-charts/spec.md`

## Summary

Improve the exercise progress charts by renaming the "Volume" metric label to "Total Volume", adding info popovers with metric descriptions, displaying units on chart axes with adaptive date formatting, and enabling tap-to-inspect data point annotations. All changes are UI-layer modifications to existing chart views and models, with localization in English and German.

## Technical Context

**Language/Version**: Swift 6 with strict concurrency
**Primary Dependencies**: SwiftUI, SwiftUI Charts framework
**Storage**: SwiftData (unchanged — no persistence changes)
**Testing**: XCTest (unit tests for formatting logic and ViewModel state)
**Target Platform**: iOS 18.5+
**Project Type**: Mobile app (iOS)
**Performance Goals**: 60 fps chart interaction, immediate tooltip response on tap
**Constraints**: Files must stay under 300 lines; DesignSystem tokens required for all styling
**Scale/Scope**: 3 modified files, 2 new view files, 2 localization files updated

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Gate | Status | Notes |
|------|--------|-------|
| I. Clean Architecture | PASS | All changes in Presentation layer (views/viewmodels) and Domain layer (model enums). No cross-layer violations. |
| II. Testing Standards | PASS | Unit tests will cover formatting helpers and ViewModel state transitions. No HealthKit/WatchConnectivity involvement. |
| III. UX Consistency | PASS | Uses DesignSystem tokens for colors, typography. Popover and annotation follow iOS conventions. Dark mode and Dynamic Type supported. Accessibility labels on info button and tooltip. |
| IV. Performance | PASS | Chart overlay gesture is lightweight. No main-thread blocking. Existing lazy loading unaffected. |
| V. Simplicity & Documentation | PASS | `/docs` file will be created/updated. No unnecessary abstractions. File extraction keeps all files under 300 lines. |

**Post-Phase 1 Re-check**: All gates still PASS. No new patterns or dependencies introduced.

## Project Structure

### Documentation (this feature)

```text
specs/001-improve-progress-charts/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0: Research findings
├── data-model.md        # Phase 1: Data model changes
├── quickstart.md        # Phase 1: Quick start guide
└── tasks.md             # Phase 2: Tasks (created by /speckit.tasks)
```

### Source Code (repository root)

```text
GymStreak/
├── Models/
│   └── ExerciseProgressModels.swift    # MODIFY: Add description properties, SelectedDataPoint
├── ViewModels/
│   └── ExerciseProgressViewModel.swift # MODIFY: Add selectedDataPoint state, selection logic
├── Views/
│   └── Charts/
│       ├── ExerciseProgressChartView.swift  # MODIFY: Axis units, info button, chart overlay
│       ├── ChartTimeframePicker.swift       # UNCHANGED
│       ├── ChartDataPointAnnotation.swift   # NEW: Floating annotation tooltip
│       └── MetricInfoPopover.swift          # NEW: Info popover content
├── Resources/
│   ├── en.lproj/Localizable.strings    # MODIFY: Add description keys, update volume label
│   └── de.lproj/Localizable.strings    # MODIFY: Same in German
docs/
└── progress-charts.md                  # NEW or UPDATE: Feature documentation
```

**Structure Decision**: No new directories needed. New view files go in the existing `Views/Charts/` directory alongside the chart views they support.

## Complexity Tracking

No constitution violations — all gates pass without justification needed.
