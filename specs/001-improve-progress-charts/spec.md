# Feature Specification: Improve Progress Charts UX

**Feature Branch**: `001-improve-progress-charts`
**Created**: 2026-04-18
**Status**: Draft
**Input**: User description: "Improve progress chart clarity: rename unclear metric labels (gesch. 1RM, Volume), add units to chart axes, and enable tapping data points to see exact values"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Clarify Metric Labels with Descriptions (Priority: P1)

As a user viewing my exercise progress, I want the metric labels to clearly describe what each metric means, so I can understand my progress without needing prior knowledge of fitness terminology.

Currently, "Gesch. 1RM" (Geschätztes 1-Repetition-Maximum) and "Volumen" are not self-explanatory. Users should immediately understand:
- **Gesch. 1RM**: This represents the estimated maximum weight the user could lift for a single repetition, calculated from their actual sets using the Epley formula.
- **Volume**: This represents the total work performed in a session, calculated as the sum of (weight x reps) across all sets.

The labels should be renamed to more descriptive alternatives, and a brief explanation should be accessible for each metric.

**Why this priority**: Without clear labels, users cannot interpret their progress data correctly, making the entire progress feature less useful.

**Independent Test**: Can be fully tested by navigating to the progress chart for any exercise and verifying that the metric picker shows clear, descriptive labels. Tapping an info element should display a brief explanation of the selected metric.

**Acceptance Scenarios**:

1. **Given** a user is on the exercise progress chart, **When** they view the metric picker, **Then** the labels read "Max Weight", "Est. 1RM", and "Total Volume"
2. **Given** a user is on the exercise progress chart, **When** they tap an info icon next to the selected metric, **Then** a brief explanation of the metric and its calculation method is displayed
3. **Given** a user switches between metrics, **When** they read the new label, **Then** they can understand what the metric represents without external help
4. **Given** the app is set to German, **When** the user views metric labels, **Then** the labels are displayed in German with equally clear descriptions

---

### User Story 2 - See Units on Chart Axes (Priority: P1)

As a user viewing progress charts, I want to see units on both the Y-axis (value) and X-axis (time), so I can accurately read the chart values and understand the scale.

**Why this priority**: Charts without units are ambiguous. Users cannot tell if the Y-axis represents kilograms, pounds, or arbitrary numbers. This is fundamental to chart readability.

**Independent Test**: Can be fully tested by viewing any exercise progress chart and verifying that both axes display appropriate units.

**Acceptance Scenarios**:

1. **Given** a user views the Max Weight chart, **When** the chart renders, **Then** the Y-axis displays the weight unit (kg) and the X-axis displays date labels
2. **Given** a user views the Est. 1RM chart, **When** the chart renders, **Then** the Y-axis displays the weight unit (kg)
3. **Given** a user views the Total Volume chart, **When** the chart renders, **Then** the Y-axis displays the volume unit (kg) with appropriate scale formatting (e.g., "1.2k kg" for large values)
4. **Given** a user views a chart with the "1W" timeframe, **When** the chart renders, **Then** the X-axis shows day-level date labels (e.g., "Mon", "Tue")
5. **Given** a user views a chart with the "1Y" or "All" timeframe, **When** the chart renders, **Then** the X-axis shows month-level date labels (e.g., "Jan", "Feb")

---

### User Story 3 - Tap Data Points to See Exact Values (Priority: P2)

As a user viewing progress charts, I want to tap on individual data points to see the exact value for that session, so I can inspect specific workout results without having to estimate from the chart grid.

**Why this priority**: While the chart provides a visual overview, users often need precise values for specific dates. This is a common and expected interaction pattern in chart UIs.

**Independent Test**: Can be fully tested by tapping on any data point in the progress chart and verifying that a tooltip or annotation appears displaying the exact value and date.

**Acceptance Scenarios**:

1. **Given** a user is viewing a progress chart with data points, **When** they tap on a data point, **Then** a floating annotation/callout anchored above the data point appears showing the exact value and the date of that session
2. **Given** a user has tapped a data point and the tooltip is visible, **When** they tap on a different data point, **Then** the tooltip moves to the new data point with updated information
3. **Given** a user has tapped a data point and the tooltip is visible, **When** they tap on an empty area of the chart (not a data point), **Then** the tooltip dismisses
4. **Given** a user taps a data point on the Max Weight chart, **When** the tooltip appears, **Then** it shows the weight value with the unit (e.g., "85 kg") and the session date
5. **Given** a user taps a data point on the Volume chart, **When** the tooltip appears, **Then** it shows the total volume with the unit and the session date
6. **Given** a chart has closely spaced data points, **When** the user taps in a crowded area, **Then** the nearest data point is selected (snap-to-nearest behavior)

---

### Edge Cases

- What happens when the chart has only 1 data point? The data point should still be tappable, and the tooltip should display correctly.
- What happens when the Y-axis values are very large (e.g., volume > 10,000 kg)? Values should use compact formatting (e.g., "10k kg").
- What happens when the Y-axis values are very small (e.g., weight < 1 kg)? Values should display with appropriate decimal precision.
- What happens when data points overlap on the X-axis (multiple sessions on the same day)? The tooltip should show the value consistent with how the chart already aggregates same-day sessions.
- What happens when the tooltip would be clipped by the edge of the screen? The tooltip should reposition to remain fully visible.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display descriptive labels for all three progress metrics in the metric picker, replacing the current abbreviated labels
- **FR-002**: System MUST display an info icon (ⓘ) next to the metric picker; tapping it shows a popover explaining what the selected metric measures and how it is calculated
- **FR-003**: System MUST display the appropriate unit on the Y-axis of all progress charts (kg for weight-based metrics, kg for volume)
- **FR-004**: System MUST display appropriately formatted date labels on the X-axis, adapting granularity to the selected timeframe (days for short timeframes, months for long timeframes)
- **FR-005**: System MUST support tapping on individual data points to reveal a floating annotation/callout anchored above the tapped point with exact values
- **FR-006**: The data point tooltip MUST display the exact metric value with unit and the session date
- **FR-007**: The tooltip MUST dismiss when tapping outside data points or when a different data point is selected
- **FR-008**: System MUST use compact number formatting for large values on the Y-axis (e.g., "1.2k" for 1,200)
- **FR-009**: All new and updated labels, tooltips, axis units, and metric descriptions MUST be localized in both English and German
- **FR-010**: The data point selection MUST use snap-to-nearest behavior when tapping near closely spaced points

### Key Entities

- **ProgressMetric**: Existing entity representing the three metric types. Updated with descriptive display names and added description/explanation text for each metric.
- **DataPointSelection**: Represents a user's selected data point on the chart, containing the associated data point and its display position for tooltip rendering.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can identify what each metric measures within 5 seconds of viewing the metric picker, without requiring external help
- **SC-002**: All chart axes display appropriate units, eliminating ambiguity in value interpretation
- **SC-003**: Users can retrieve the exact value of any data point within 2 seconds by tapping on it
- **SC-004**: 100% of user-facing text (labels, tooltips, axis units, metric descriptions) is available in both English and German
- **SC-005**: Tooltip interaction feels responsive and natural, with immediate visual feedback on tap

## Clarifications

### Session 2026-04-18

- Q: What should the final metric label names be? → A: "Max Weight", "Est. 1RM", "Total Volume"
- Q: How should metric explanations be presented? → A: Info icon (ⓘ) next to metric picker; tap shows popover with explanation
- Q: What visual style for tapped data point tooltips? → A: Floating annotation/callout anchored above the tapped data point (value + date)

## Assumptions

- The app currently uses kilograms (kg) as the weight unit. If pound support is added in the future, the axis units would need to adapt, but this is out of scope for this feature.
- The existing chart layout has sufficient space to accommodate axis labels and tooltips without major layout restructuring.
- The Epley formula explanation in the metric info is sufficient for users; no need for alternative formula options.
- The existing data point rendering provides adequate tap targets; if points are too small, minor size adjustments may be needed but are considered implementation details.
- Compact number formatting follows standard conventions (e.g., 1,000 = "1k", 1,000,000 = "1M").
