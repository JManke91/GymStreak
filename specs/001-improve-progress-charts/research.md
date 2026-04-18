# Research: Improve Progress Charts UX

**Branch**: `001-improve-progress-charts` | **Date**: 2026-04-18

## R1: SwiftUI Charts — Interactive Data Point Selection

**Decision**: Use `chartOverlay` with `GeometryProxy` + `ChartProxy` to detect tap gestures, then convert tap location to data values using `chart.value(atX:)` to find the nearest data point.

**Rationale**: This is Apple's recommended pattern for interactive charts in SwiftUI. It provides precise coordinate mapping between gesture location and chart data values. The `chartOverlay` modifier keeps the interaction logic cleanly separated from chart rendering.

**Alternatives considered**:
- `chartGesture`: Lower-level, less suited for discrete point selection
- Wrapping each PointMark in a Button: Not supported by SwiftUI Charts
- `onTapGesture` on Chart: Doesn't provide chart-relative coordinates

**Implementation pattern**:
```swift
.chartOverlay { proxy in
    GeometryReader { geo in
        Rectangle().fill(.clear).contentShape(Rectangle())
            .onTapGesture { location in
                let origin = geo[proxy.plotAreaFrame].origin
                let adjustedLocation = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
                if let date: Date = proxy.value(atX: adjustedLocation.x) {
                    // Find nearest data point by date
                }
            }
    }
}
```

## R2: Floating Annotation/Callout Rendering

**Decision**: Use a `chartAnnotation` modifier on a `RuleMark` placed at the selected data point's position. The annotation renders a small card with value + date, anchored above the point.

**Rationale**: `chartAnnotation` is the native SwiftUI Charts approach for anchored overlays. It automatically handles positioning relative to the chart and avoids manual coordinate tracking. Using a `RuleMark` as the anchor allows a vertical highlight line at the selected point.

**Alternatives considered**:
- ZStack overlay with manual positioning: Fragile, requires coordinate translation
- `.popover` modifier: Too heavy for a simple value display, doesn't anchor to chart points
- Custom overlay with GeometryReader: More code, no automatic repositioning

## R3: Compact Number Formatting for Y-Axis

**Decision**: Use a custom formatter that abbreviates values ≥ 1,000 as "1k", ≥ 10,000 as "10k", etc. Apply via `AxisValueLabel` with formatted text.

**Rationale**: SwiftUI Charts' built-in formatting doesn't support compact abbreviations with units. A small helper function keeps the formatting consistent across Y-axis labels and tooltip values.

**Format rules**:
- < 1: Show 1 decimal (e.g., "0.5")
- 1–999: Show integer (e.g., "85")
- 1,000–999,999: Show with "k" suffix (e.g., "1.2k")
- ≥ 1,000,000: Show with "M" suffix (e.g., "1.2M")

## R4: X-Axis Date Formatting by Timeframe

**Decision**: Use `AxisMarks` with timeframe-dependent `DateComponents` stride and `DateFormatter` patterns.

**Mapping**:
| Timeframe | Stride | Format (EN) | Format (DE) |
|-----------|--------|-------------|-------------|
| 1W | .day | "Mon" | "Mo" |
| 1M | .weekOfYear | "MMM d" | "d. MMM" |
| 3M | .month | "MMM" | "MMM" |
| 1Y | .month(2) | "MMM" | "MMM" |
| All | .month(3) | "MMM yy" | "MMM yy" |

**Rationale**: Adapting axis granularity to the timeframe prevents label overcrowding on short ranges and ensures readability on long ranges. Using locale-aware DateFormatter ensures correct German formatting.

## R5: Info Popover for Metric Descriptions

**Decision**: Add a small ⓘ button next to the metric picker. Tapping it shows a `.popover` with a brief metric description. Each `ProgressMetric` case will have a `localizedDescription` computed property.

**Metric descriptions**:
- **Max Weight**: "The heaviest weight lifted in a single set during the session."
- **Est. 1RM**: "Estimated one-rep max — the maximum weight you could lift once, calculated from your sets using the Epley formula (weight × (1 + reps ÷ 30))."
- **Total Volume**: "Total work performed — the sum of weight × reps across all sets in the session."

**Rationale**: A popover is lightweight, dismisses on tap-outside, and is the standard iOS pattern for contextual info. It avoids cluttering the chart view with always-visible text.

## R6: File Size Consideration

**Current state**: `ExerciseProgressChartView.swift` is 311 lines, already exceeding the 300-line constitution limit. Adding tap interaction, annotation overlay, and info popover will increase it further.

**Decision**: Extract the annotation/tooltip component and the chart interaction logic into a separate file (`ChartDataPointAnnotation.swift` or similar). The info popover can also be a small standalone view. This keeps all files under 300 lines.

## R7: Volume Unit Display

**Current state**: Volume's `unit` property returns "kg", which is technically incorrect — volume is weight × reps, so the unit is "kg" (the reps are dimensionless). However, displaying "kg×reps" is unusual in fitness apps.

**Decision**: Keep "kg" as the Y-axis unit for volume. This is consistent with how all major fitness apps display volume. The info popover will clarify that volume = weight × reps.
