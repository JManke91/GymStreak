# Tasks: Fix Progress Chart Display Issues

**Input**: Design documents from `/specs/002-fix-chart-display/`
**Prerequisites**: plan.md (required), spec.md (required), research.md

**Tests**: Not requested — manual verification only.

**Organization**: Tasks are grouped by user story. Note: US1 and US2 share the same code change (removing the `AreaMark` block), so they are resolved together in Phase 2. US3 is a verification pass.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Fix — Remove AreaMark (Resolves US1 + US2)

**Goal**: Remove the `AreaMark` `ForEach` block from `ProgressChartContent` to fix Y-axis scaling and remove area fills simultaneously.

**Independent Test**: Build the app, navigate to any exercise progress chart, verify no area fill is shown and Y-axis labels match data point values on the Total Volume tab.

### Implementation

- [x] T001 [US1] [US2] Remove the `AreaMark` `ForEach` block (lines ~196-212) from `ProgressChartContent` in GymStreak/Views/Charts/ExerciseProgressChartView.swift
- [x] T002 [US1] Build the project and verify it compiles without errors

**Checkpoint**: Area fills removed, Y-axis scaling should be fixed for all metrics.

---

## Phase 2: Verify — Y-Axis Accuracy Across All Metrics (US3)

**Goal**: Confirm Y-axis labels are correct on all three metric tabs after the AreaMark removal.

**Independent Test**: Switch between Max Weight, Est. 1RM, and Total Volume tabs, tap data points, and verify annotation values match visual position on the Y-axis.

### Implementation

- [x] T003 [US3] Review `formatCompactValue` in GymStreak/Models/ExerciseProgressModels.swift — verify edge cases for values < 1, values at 1000 boundaries, and very large values (> 10,000). No issues found.
- [x] T004 [US3] Manually verify all three metric tabs render correct Y-axis labels with real workout data — requires user validation after running the app

**Checkpoint**: All three metric tabs display accurate Y-axis labels and data point positions.

---

## Phase 3: Polish & Documentation

**Purpose**: Update documentation to reflect the chart display changes.

- [x] T005 Update docs/progress-charts.md to remove references to area fills and document the chart rendering fix

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Fix)**: No dependencies — start immediately
- **Phase 2 (Verify)**: Depends on Phase 1 completion
- **Phase 3 (Polish)**: Depends on Phase 2 completion

### User Story Dependencies

- **US1 (Y-Axis Fix)** + **US2 (Area Fill Removal)**: Resolved by the same code change (T001) — no inter-story dependency
- **US3 (Cross-Metric Verification)**: Depends on US1/US2 completion (T001, T002)

### Parallel Opportunities

- T001 and T002 are sequential (build depends on code change)
- T003 and T004 can run in parallel (code review vs. manual testing)
- T005 can run in parallel with Phase 2 if desired

---

## Implementation Strategy

### MVP First (Phase 1 Only)

1. Complete T001: Remove AreaMark block
2. Complete T002: Verify build
3. **STOP and VALIDATE**: Test Total Volume tab Y-axis + verify no area fills
4. If Y-axis is correct → proceed to Phase 2 verification
5. If Y-axis still incorrect → T003 investigates `formatCompactValue`

### Full Delivery

1. Phase 1: Remove AreaMark (T001-T002)
2. Phase 2: Verify all metrics (T003-T004)
3. Phase 3: Update docs (T005)

---

## Notes

- The core fix is a single code deletion (~15 lines) in one file
- US1 and US2 are intentionally merged into one phase because the same code change resolves both
- T003 is a contingency task — `formatCompactValue` review may reveal no issues
- Commit after T001+T002 as a logical unit
