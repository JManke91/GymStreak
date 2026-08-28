//
//  ChartSeries.swift
//  GymStreak
//
//  The progress chart's plotted series, in display units. See
//  docs/weight-unit-preference.md §8.
//

import Foundation

/// The plotted series in **display** space, together with the y-domain derived
/// from the same converted numbers.
///
/// Built once per load, metric change or unit change — never in a view body. Two
/// reasons, and both were live defects waiting to happen: the marks and
/// `chartYScale(domain:)` have to convert *together* or the scale describes a
/// different unit than the line it bounds; and the domain used to be a computed
/// property read from inside the very `ForEach` that drew the points
/// (`AreaMark`'s `yStart`), so it mapped over the whole series once per point.
/// Converting in there would have multiplied an already O(n²) read.
///
/// The canonical `ExerciseProgressDataPoint` travels along in each point, so a
/// tap hands the *unconverted* value back and the selection is still resolved in
/// kilograms.
///
/// It lives in `Presentation/` rather than beside `ExerciseProgressData`: it
/// holds *display-space* numbers, and putting the kilograms→pounds conversion in
/// `Domain/Models/` would be the same leak that removing `ProgressMetric.unit`
/// was meant to close.
struct ChartSeries: Sendable {

    struct Point: Identifiable, Sendable {
        /// The point this was converted from, in canonical kilograms.
        let source: ExerciseProgressDataPoint
        /// `source`'s value for the charted metric, in display units.
        let value: Double

        var id: UUID { source.id }
        var date: Date { source.date }
    }

    let points: [Point]
    let yDomain: ClosedRange<Double>

    /// Whether the y-axis may use compact notation.
    ///
    /// `formatCompactValue` renders a value ≥1000 as one decimal of thousands,
    /// so its resolution there is 100 units. A domain narrower than that prints
    /// the *same label on every gridline* — observed as four rows all reading
    /// "1,1k" on a pounds volume chart, and as "1,1k / 1,1k / 1k / 950" on a
    /// kilogram one. Pre-existing, but pounds multiply every volume by 2.2 and
    /// so turn a rare case into the common one.
    ///
    /// Below 1000 the function does not compact at all, so the flag only bites
    /// where it must.
    var axisUsesCompactNotation: Bool {
        yDomain.upperBound - yDomain.lowerBound >= 1000
    }

    /// One y-axis gridline label. Plain when compacting would collapse the axis.
    func axisLabel(for value: Double) -> String {
        axisUsesCompactNotation
            ? formatCompactValue(value)
            : value.formatted(Self.plainAxisStyle)
    }

    private static let plainAxisStyle = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(0))
        .grouping(.never)

    /// Builds a series from an already-converted domain, so the axis rule can be
    /// exercised against a chosen domain without fabricating a whole
    /// `ExerciseProgressData` to imply one.
    init(points: [Point], yDomain: ClosedRange<Double>) {
        self.points = points
        self.yDomain = yDomain
    }

    init(data: ExerciseProgressData, metric: ProgressMetric, unit: WeightUnit) {
        points = data.dataPoints.map {
            Point(
                source: $0,
                value: unit.converting(fromKilograms: $0.value(for: metric))
            )
        }
        yDomain = Self.domain(for: points.map(\.value))
    }

    /// A 10%-padded window around the series, floored at zero, with a fallback
    /// for a flat or empty series — Swift Charts needs a non-degenerate range.
    private static func domain(for values: [Double]) -> ClosedRange<Double> {
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let padding = max((maxValue - minValue) * 0.1, maxValue * 0.05)
        let lower = max(0, minValue - padding)
        let upper = maxValue + padding
        guard lower < upper else {
            let fallback = max(maxValue * 0.1, 1)
            return max(0, maxValue - fallback)...(maxValue + fallback)
        }
        return lower...upper
    }
}
