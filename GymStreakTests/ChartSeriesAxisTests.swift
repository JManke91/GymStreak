//
//  ChartSeriesAxisTests.swift
//  GymStreakTests
//
//  The progress chart's y-axis compacts a value ≥1000 to one decimal of
//  thousands, so its resolution there is 100 units. On a domain narrower than
//  that every gridline printed the same label — four rows reading "1,1k" on a
//  pounds volume chart, "1,1k / 1,1k / 1k / 950" on a kilogram one. Pre-existing,
//  and routine once pounds multiply every volume by 2.2.
//
//  See docs/weight-unit-preference.md §8.
//

import Testing
import Foundation
@testable import GymStreak

@MainActor
struct ChartSeriesAxisTests {

    private func labels(_ domain: ClosedRange<Double>, count: Int = 4) -> [String] {
        let series = ChartSeries(points: [], yDomain: domain)
        let step = (domain.upperBound - domain.lowerBound) / Double(count - 1)
        return (0..<count).map {
            series.axisLabel(for: domain.lowerBound + step * Double($0))
        }
    }

    @Test("A narrow domain above 1000 gets distinct labels, not four identical ones")
    func narrowDomainDoesNotCollapse() {
        // Shoulder Press in pounds: 3 × 28 kg × 6 ≈ 1111 lb, a nearly flat series.
        let pounds = labels(1100...1120)
        #expect(Set(pounds).count == pounds.count)
        // Inclined Flying in kilograms — the same collapse, one unit over.
        let kilograms = labels(950...1100)
        #expect(Set(kilograms).count == kilograms.count)
    }

    @Test("A domain wide enough to survive it still compacts")
    func wideDomainStillCompacts() {
        let series = ChartSeries(points: [], yDomain: 500...12_500)
        #expect(series.axisUsesCompactNotation)
        #expect(series.axisLabel(for: 12_500) == formatCompactValue(12_500))
    }

    @Test("A domain below the compaction threshold is unaffected")
    func smallDomainIsUnchanged() {
        // `formatCompactValue` does not compact under 1000 anyway, so the flag
        // must not change what these render as.
        let series = ChartSeries(points: [], yDomain: 280...340)
        #expect(series.axisLabel(for: 340) == formatCompactValue(340))
    }
}
