//
//  RoutineMetricsServiceTests.swift
//  GymStreakTests
//
//  Pins the Domain layer out of the weight-formatting business.
//

import Testing
@testable import GymStreak

@Suite
struct RoutineMetricsServiceTests {

    @Test
    func setSchemeSummaryRendersTheWeightThroughTheCallersFormatter() {
        let summary = RoutineMetricsService.setSchemeSummary(
            reps: [10, 10, 10],
            weights: [20, 20, 20],
            formattingWeight: { "<\($0)>" }
        )

        #expect(summary == "3×10 · <20.0>")
        // The service used to interpolate "%gkg" itself. Nothing it produces may
        // carry a unit word — it has no way of knowing which one the user reads.
        #expect(summary?.contains("kg") == false)
        #expect(summary?.contains("lb") == false)
    }

    @Test
    func setSchemeSummaryNeverCallsTheFormatterWithoutOneUniformNonZeroWeight() {
        var formatted: [Double] = []
        let record: (Double) -> String = { formatted.append($0); return "" }

        // Bodyweight scheme: alternatives commonly seed every set at 0.
        #expect(RoutineMetricsService.setSchemeSummary(
            reps: [8, 8], weights: [0, 0], formattingWeight: record
        ) == "2×8")

        // Pyramid: no single weight describes the exercise.
        #expect(RoutineMetricsService.setSchemeSummary(
            reps: [12, 10, 8], weights: [20, 25, 30], formattingWeight: record
        ) == "3×8–12")

        #expect(formatted.isEmpty)
        #expect(RoutineMetricsService.setSchemeSummary(
            reps: [], weights: [], formattingWeight: record
        ) == nil)
    }
}
