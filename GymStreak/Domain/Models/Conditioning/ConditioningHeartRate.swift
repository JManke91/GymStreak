//
//  ConditioningHeartRate.swift
//  GymStreak
//
//  A finished conditioning session's heart rate, read back from Apple Health for
//  its share card. `ConditioningRecord` stores none of it; the summary is computed
//  by `ConditioningHeartRateSummarizer`. See docs/workout-sharing.md.
//

import Foundation

/// One heart-rate value as Apple Health stores it. A reading that spans a period
/// (`end > start`) holds its value for that period.
struct HeartRateReading: Equatable, Sendable {
    let start: Date
    let end: Date
    let bpm: Double
}

/// What a session's heart rate adds to its share card.
struct ConditioningHeartRateSummary: Equatable, Sendable {
    /// Time-weighted over the measured time.
    let averageBPM: Int
    let maxBPM: Int
    /// Seconds spent in each zone, Z1 first. `nil` without a usable heart-rate profile
    /// (none, invalid, or the medication switch): the average and maximum still count.
    let zoneSeconds: [TimeInterval]?
}
