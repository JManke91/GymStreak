//
//  ConditioningHeartRateSummarizerTests.swift
//  GymStreakTests
//
//  The share card's heart-rate numbers: time-weighted average, maximum, time per zone,
//  the gap cap and the coverage threshold. See docs/workout-sharing.md.
//

import Foundation
import Testing
@testable import GymStreak

struct ConditioningHeartRateSummarizerTests {

    private let start = Date(timeIntervalSinceReferenceDate: 0)

    /// A watch-workout-like stream: one reading every 5 s.
    private func stream(_ bpms: [Double], every interval: TimeInterval = 5) -> [HeartRateReading] {
        bpms.enumerated().map { index, bpm in
            let date = start.addingTimeInterval(Double(index) * interval)
            return HeartRateReading(start: date, end: date, bpm: bpm)
        }
    }

    @Test
    func averageIsTimeWeightedAndMaxIsThePeak() throws {
        // 10 s at 100, 10 s at 160 (last reading held to the window end).
        let readings = stream([100, 100, 160, 160])
        let summary = try #require(ConditioningHeartRateSummarizer.summarize(
            readings, from: start, to: start.addingTimeInterval(20), zoneFloors: nil
        ))
        #expect(summary.averageBPM == 130)
        #expect(summary.maxBPM == 160)
        #expect(summary.zoneSeconds == nil)
    }

    @Test
    func timeIsSortedIntoZonesAndBelowZoneOneCountsAsZoneOne() throws {
        let floors = [95, 114, 133, 152, 171] // HRmax 190
        let readings = stream([80, 120, 140, 160, 180, 180])
        let summary = try #require(ConditioningHeartRateSummarizer.summarize(
            readings, from: start, to: start.addingTimeInterval(30), zoneFloors: floors
        ))
        #expect(summary.zoneSeconds == [5, 5, 5, 5, 10])
    }

    @Test
    func aDropoutIsNotCountedAsTimeAtTheLastValue() throws {
        // 60 s window: readings for the first 40 s, then nothing.
        let readings = stream(Array(repeating: 150, count: 8))
        let summary = try #require(ConditioningHeartRateSummarizer.summarize(
            readings, from: start, to: start.addingTimeInterval(60), zoneFloors: [0, 1, 2, 3, 200]
        ))
        // 7 × 5 s plus the last reading's 15 s cap.
        #expect(summary.zoneSeconds?.reduce(0, +) == 50)
    }

    @Test
    func sparseBackgroundReadingsAreNoSummary() {
        // A watch outside a workout: one reading every 5 minutes over 30 minutes.
        let readings = stream([90, 95, 100, 92, 97, 99], every: 300)
        #expect(ConditioningHeartRateSummarizer.summarize(
            readings, from: start, to: start.addingTimeInterval(1800), zoneFloors: nil
        ) == nil)
    }

    @Test
    func readingsOutsideTheWindowAreIgnored() throws {
        let before = HeartRateReading(start: start.addingTimeInterval(-60), end: start.addingTimeInterval(-60), bpm: 200)
        let readings = [before] + stream([120, 120, 120])
        let summary = try #require(ConditioningHeartRateSummarizer.summarize(
            readings, from: start, to: start.addingTimeInterval(15), zoneFloors: nil
        ))
        #expect(summary.maxBPM == 120)
    }

    @Test
    func noReadingsIsNoSummary() {
        #expect(ConditioningHeartRateSummarizer.summarize(
            [], from: start, to: start.addingTimeInterval(600), zoneFloors: nil
        ) == nil)
    }

    // MARK: - Zone floors

    @Test
    func sessionZonesArePercentOfMaxEvenWithARestingHeartRate() {
        let profile = HeartRateProfile(maxSource: .measured, measuredMaxHeartRate: 200, restingHeartRate: 60)
        #expect(HeartRateZones.sessionZoneFloors(for: profile) == [100, 120, 140, 160, 180])
    }

    @Test
    func noZonesWithoutAUsableProfileOrWithMedication() {
        #expect(HeartRateZones.sessionZoneFloors(for: nil) == nil)
        #expect(HeartRateZones.sessionZoneFloors(for: HeartRateProfile(age: nil)) == nil)
        #expect(HeartRateZones.sessionZoneFloors(
            for: HeartRateProfile(age: 30, usesHeartRateMedication: true)
        ) == nil)
    }
}
