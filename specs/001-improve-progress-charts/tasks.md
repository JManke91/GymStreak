# Tasks: Improve Progress Charts UX

**Input**: Design documents from `/specs/001-improve-progress-charts/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, quickstart.md

**Tests**: Not explicitly requested in the feature specification. Test tasks are omitted.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Add all new localization strings needed across user stories

- [x] T001 Add new metric description localization keys and update volume label in GymStreak/Resources/en.lproj/Localizable.strings and GymStreak/Resources/de.lproj/Localizable.strings — keys: `chart.metric.volume` (update to "Total Volume"/"Gesamtvolumen"), `chart.metric.max_weight.description`, `chart.metric.estimated_1rm.description`, `chart.metric.volume.description`, `chart.tooltip.date_label`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared formatting utility used by both US2 (axis labels) and US3 (tooltip values)

- [x] T002 Add compact number formatting helper function to GymStreak/Models/ExerciseProgressModels.swift — format rules: <1 → "0.5", 1–999 → "85", 1k–999k → "1.2k", ≥1M → "1.2M"; append unit suffix (e.g., "kg") when provided

**Checkpoint**: Foundation ready — user story implementation can now begin

---

## Phase 3: User Story 1 — Clarify Metric Labels with Descriptions (Priority: P1) MVP

**Goal**: Rename "Volume" to "Total Volume" in the metric picker and add an info icon (ⓘ) that shows a popover explaining each metric's meaning and calculation method.

**Independent Test**: Navigate to History → Progress → select any exercise. Verify metric picker shows "Max Weight", "Est. 1RM", "Total Volume". Tap ⓘ icon → popover explains the selected metric. Switch to German → labels show "Max. Gewicht", "Gesch. 1RM", "Gesamtvolumen".

### Implementation for User Story 1

- [x] T003 [US1] Update `localizedTitle` for the `.volume` case of `ProgressMetric` to use the updated `chart.metric.volume` key ("Total Volume") in GymStreak/Models/ExerciseProgressModels.swift
- [x] T004 [US1] Add `localizedDescription` computed property to `ProgressMetric` enum returning localized explanation text for each metric in GymStreak/Models/ExerciseProgressModels.swift
- [x] T005 [US1] Create MetricInfoPopover view that displays a metric's `localizedDescription` text, styled with DesignSystem tokens, in GymStreak/Views/Charts/MetricInfoPopover.swift
- [x] T006 [US1] Add ⓘ info button next to the metric Picker in ExerciseProgressChartView that triggers a `.popover` presenting MetricInfoPopover for the selected metric, with accessibility label, in GymStreak/Views/Charts/ExerciseProgressChartView.swift

**Checkpoint**: Metric labels are clear and self-explanatory. Info popover works for all three metrics in EN and DE.

---

## Phase 4: User Story 2 — See Units on Chart Axes (Priority: P1)

**Goal**: Display "kg" unit on the Y-axis with compact formatting for large values, and show timeframe-adaptive date labels on the X-axis.

**Independent Test**: View any exercise progress chart. Y-axis shows values with "kg" suffix (e.g., "85 kg", "1.2k kg"). X-axis shows day names for 1W, month abbreviations for 1Y/All. Change timeframes to verify adaptive formatting.

### Implementation for User Story 2

- [x] T007 [P] [US2] Add `axisStrideComponent` (Calendar.Component), `axisStrideValue` (Int), and date format helper to `ChartTimeframe` enum in GymStreak/Models/ExerciseProgressModels.swift — mapping: 1W→.day/1, 1M→.weekOfYear/1, 3M→.month/1, 1Y→.month/2, All→.month/3
- [x] T008 [US2] Update Y-axis `AxisMarks` in `ProgressChartContent` to display compact-formatted values with "kg" unit suffix using the helper from T002, in GymStreak/Views/Charts/ExerciseProgressChartView.swift
- [x] T009 [US2] Update X-axis `AxisMarks` in `ProgressChartContent` to use timeframe-dependent stride from `ChartTimeframe` properties and locale-aware date formatting, in GymStreak/Views/Charts/ExerciseProgressChartView.swift

**Checkpoint**: All chart axes show appropriate units. Y-axis uses compact formatting. X-axis adapts granularity to the selected timeframe.

---

## Phase 5: User Story 3 — Tap Data Points to See Exact Values (Priority: P2)

**Goal**: Enable tapping data points to show a floating annotation/callout anchored above the point, displaying the exact metric value with unit and session date. Tap elsewhere to dismiss.

**Independent Test**: View any exercise progress chart with data. Tap a data point → floating annotation appears above it showing value (e.g., "85 kg") and date. Tap another point → annotation moves. Tap empty area → annotation dismisses. Test with all three metrics.

### Implementation for User Story 3

- [x] T010 [P] [US3] Add `SelectedDataPoint` struct (dataPoint, displayValue, displayDate) to GymStreak/Models/ExerciseProgressModels.swift
- [x] T011 [P] [US3] Add `@Published var selectedDataPoint: SelectedDataPoint?` to ExerciseProgressViewModel with `selectDataPoint(_:for:)` and `clearSelection()` methods; format value using compact formatter and locale-aware date in GymStreak/ViewModels/ExerciseProgressViewModel.swift
- [x] T012 [P] [US3] Create ChartDataPointAnnotation view that renders a small styled card (DesignSystem tokens) showing displayValue and displayDate, anchored via `chartAnnotation`, in GymStreak/Views/Charts/ChartDataPointAnnotation.swift
- [x] T013 [US3] Add `chartOverlay` with `GeometryReader`/`ChartProxy` tap gesture to find nearest data point by date, conditional `RuleMark` at selected point with `chartAnnotation` using ChartDataPointAnnotation, and tap-to-dismiss on empty area, in GymStreak/Views/Charts/ExerciseProgressChartView.swift; clear selection on metric/timeframe/exercise change

**Checkpoint**: Data point tap interaction works for all metrics. Tooltip shows correct value and date. Dismisses properly.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, file size compliance, and build verification

- [x] T014 [P] Create or update docs/progress-charts.md documenting the progress feature: purpose, architecture, components (ExerciseProgressChartView, ExerciseProgressViewModel, ExerciseProgressModels, ChartDataPointAnnotation, MetricInfoPopover, ChartTimeframePicker), data flow, and both iOS target considerations
- [x] T015 Verify all modified/new files are under 300 lines — if ExerciseProgressChartView.swift exceeds limit, extract ProgressChartContent or SummaryStatsView into separate files in GymStreak/Views/Charts/
- [x] T016 Build both iOS and watchOS targets (Cmd+B) to verify no compilation errors or warnings

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: No strict dependency on Phase 1, but logically follows it
- **User Stories (Phase 3–5)**: All depend on Phase 1 (localization strings) and Phase 2 (formatter)
  - US1 and US2 are both P1 and can proceed in parallel after Phase 2
  - US3 can proceed in parallel with US1/US2 after Phase 2
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Phase 2 — No dependencies on other stories
- **User Story 2 (P1)**: Can start after Phase 2 — No dependencies on other stories
- **User Story 3 (P2)**: Can start after Phase 2 — No dependencies on other stories (uses same formatter from T002)

### Within Each User Story

- Model changes before view changes
- ViewModel changes before view integration
- New view files before integrating them into ExerciseProgressChartView

### Parallel Opportunities

- T007 can run in parallel with T003–T006 (different enum, no conflicts)
- T010, T011, T012 can all run in parallel (different files)
- T014 can run in parallel with T015 and T016
- All three user stories can start in parallel after Phase 2 if desired

---

## Parallel Example: User Story 3

```text
# Launch all parallelizable US3 tasks together:
Task: "T010 - Add SelectedDataPoint struct in ExerciseProgressModels.swift"
Task: "T011 - Add selectedDataPoint state to ExerciseProgressViewModel.swift"
Task: "T012 - Create ChartDataPointAnnotation.swift"

# Then sequentially:
Task: "T013 - Add chartOverlay + RuleMark annotation to ExerciseProgressChartView.swift"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Localization strings
2. Complete Phase 2: Compact number formatter
3. Complete Phase 3: User Story 1 (metric labels + info popover)
4. **STOP and VALIDATE**: Test metric labels and info popover independently
5. Build and verify

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently (MVP — clear labels + info)
3. Add User Story 2 → Test independently (axis units + formatting)
4. Add User Story 3 → Test independently (tap-to-inspect tooltips)
5. Polish → Documentation + build verification
6. Each story adds value without breaking previous stories

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- ExerciseProgressChartView.swift is already 311 lines — T015 ensures it stays within the 300-line constitution limit after all modifications
- All styling must use DesignSystem tokens (colors, typography, spacing)
- Accessibility labels required on info button and tooltip elements
- Selection must clear when metric, timeframe, or exercise changes to avoid stale tooltips
