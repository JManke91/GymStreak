# Feature Specification: Fix Progress Chart Display Issues

**Feature Branch**: `002-fix-chart-display`
**Created**: 2026-04-18
**Status**: Draft
**Input**: User description: "Fix Y-axis unit display bug on Total Volume tab and evaluate/remove area fills from all chart tabs"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Correct Y-Axis Scale on Total Volume Tab (Priority: P1)

As a user viewing the Total Volume progress chart, I expect the Y-axis labels to accurately reflect the scale of my volume data, so I can correctly interpret my training progress at a glance.

**Why this priority**: The Y-axis currently shows values like "0 kg" and "1 kg" while data points display values like "400 kg". This is a systematic data display bug that makes the chart fundamentally unreadable and misleading for the Total Volume metric.

**Independent Test**: Can be fully tested by navigating to any exercise's progress chart, selecting the Total Volume tab, and verifying that the Y-axis labels match the scale of the displayed data points.

**Acceptance Scenarios**:

1. **Given** a user has workout history with total volume values (e.g., 400 kg), **When** they view the Total Volume chart tab, **Then** the Y-axis labels must correctly reflect the data range (e.g., showing "0 kg", "200 kg", "400 kg" or appropriate compact notation like "0.4k kg").
2. **Given** a user taps on a data point showing "400 kg", **When** they look at the Y-axis, **Then** the data point must visually sit at a position consistent with the Y-axis scale (i.e., near the "400 kg" mark, not near "0 kg" or "1 kg").
3. **Given** volume values span a large range (e.g., 500 to 5000 kg), **When** the chart renders, **Then** the Y-axis must use appropriate compact notation (e.g., "1k kg", "5k kg") and the axis range must encompass all data points.

---

### User Story 2 - Remove Area Fills from All Chart Tabs (Priority: P2)

As a user viewing progress charts, I want to see clean line charts without gradient area fills, so the chart is easier to read and the visual presentation is not cluttered with unnecessary decorative elements.

**Why this priority**: The area fills (gradient shading under the line) appear on all three tabs (Max Weight, Est. 1RM, Total Volume) and add visual noise without conveying additional meaningful information. Removing them improves chart readability.

**Independent Test**: Can be fully tested by navigating to any exercise's progress chart and verifying that each tab (Max Weight, Est. 1RM, Total Volume) shows only the line connecting data points and the data point markers, without any filled/shaded area beneath the line.

**Acceptance Scenarios**:

1. **Given** a user views the Max Weight chart tab, **When** the chart renders, **Then** only the line and point markers are displayed with no gradient area fill beneath the line.
2. **Given** a user views the Estimated 1RM chart tab, **When** the chart renders, **Then** only the line and point markers are displayed with no gradient area fill beneath the line.
3. **Given** a user views the Total Volume chart tab, **When** the chart renders, **Then** only the line and point markers are displayed with no gradient area fill beneath the line.

---

### User Story 3 - Consistent Y-Axis Accuracy Across All Metrics (Priority: P2)

As a user, I expect all chart tabs (Max Weight, Est. 1RM, Total Volume) to display accurate and correctly scaled Y-axis labels, so that the visual position of data points matches their actual values.

**Why this priority**: While the user specifically reported the issue on the Total Volume tab, the same rendering logic is shared across all three metrics. A systematic investigation should verify correctness across all tabs to prevent similar issues.

**Independent Test**: Can be tested by viewing each metric tab with known workout data and verifying Y-axis labels accurately reflect the data range.

**Acceptance Scenarios**:

1. **Given** a user views Max Weight data with values around 80 kg, **When** the chart renders, **Then** the Y-axis shows appropriate labels (e.g., "0 kg", "40 kg", "80 kg") and data points are positioned correctly.
2. **Given** a user views Estimated 1RM data with values around 100 kg, **When** the chart renders, **Then** the Y-axis shows appropriate labels and data points are positioned correctly.

---

### Edge Cases

- What happens when volume values are very small (e.g., < 1 kg)?
- What happens when volume values are very large (e.g., > 10,000 kg)?
- How does the chart display with only a single data point?
- How does the Y-axis scale when all data points have the same value?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display Y-axis labels that accurately represent the scale and range of the charted data for all metrics (Max Weight, Est. 1RM, Total Volume).
- **FR-002**: System MUST ensure the visual position of each data point on the chart corresponds to its actual value relative to the Y-axis scale.
- **FR-003**: System MUST NOT render area fills (gradient shading beneath the line) on any of the three chart tabs.
- **FR-004**: System MUST continue to display line marks connecting data points and point markers at each data point.
- **FR-005**: System MUST use compact number notation on Y-axis labels when values are large (e.g., "1k kg" for 1000 kg).
- **FR-006**: System MUST ensure the data point annotation (shown on tap) displays a value consistent with the Y-axis scale.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For any data point tapped, the displayed value and the visual position on the chart are consistent with the Y-axis scale — no mismatch between annotation value and visual position.
- **SC-002**: All three chart tabs render without gradient area fills beneath the line.
- **SC-003**: Y-axis labels span a range that encompasses all visible data points with appropriate increments.

## Assumptions

- The underlying data (totalVolume, maxWeight, estimated1RM) calculated in the service layer is correct; this fix addresses the display/rendering layer only.
- The compact number formatting function (`formatCompactValue`) may need investigation as a potential root cause of the Y-axis labeling issue.
- The area fill removal is a visual design decision — no data or functionality is lost by removing the `AreaMark`.
- The existing chart interaction behavior (tap to select data points, annotation display) remains unchanged.
