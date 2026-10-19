//
//  ConditioningHeartRateSummarizer.swift
//  GymStreak
//
//  Folds the heart-rate readings of a session's time window into its average,
//  maximum and time per zone. Pure logic. See docs/workout-sharing.md.
//

import Foundation

enum ConditioningHeartRateSummarizer {

    /// A reading holds its value until the next one, but never longer than this, so a
    /// dropout is not counted as minutes at the last value. Same cap as the watch's
    /// mat-session tally.
    static let maximumGap: TimeInterval = 15
    /// Below this share of the session measured, the numbers would describe a few stray
    /// readings (a watch outside a workout samples every few minutes), not the session.
    static let minimumCoverage = 0.5

    /// - Parameter zoneFloors: the lowest bpm of each zone, Z1 first
    ///   (`HeartRateZones.sessionZoneFloors`). Time below Z1 counts as Z1.
    /// - Returns: `nil` when less than `minimumCoverage` of the window was measured.
    static func summarize(
        _ readings: [HeartRateReading],
        from start: Date,
        to end: Date,
        zoneFloors: [Int]?
    ) -> ConditioningHeartRateSummary? {
        let duration = end.timeIntervalSince(start)
        guard duration > 0 else { return nil }
        let sorted = readings
            .filter { $0.end >= start && $0.start <= end }
            .sorted { $0.start < $1.start }

        var measured: TimeInterval = 0
        var weighted = 0.0
        var peak = 0.0
        var zones = zoneFloors.map { Array(repeating: TimeInterval(0), count: $0.count) }

        for (index, reading) in sorted.enumerated() {
            let next = index + 1 < sorted.count ? sorted[index + 1].start : end
            let holdsUntil = max(reading.end, reading.start.addingTimeInterval(maximumGap))
            let seconds = min(next, holdsUntil, end).timeIntervalSince(max(reading.start, start))
            peak = max(peak, reading.bpm)
            guard seconds > 0 else { continue }
            measured += seconds
            weighted += reading.bpm * seconds
            if let floors = zoneFloors {
                let zone = floors.lastIndex { Double($0) <= reading.bpm } ?? 0
                zones?[zone] += seconds
            }
        }

        guard measured > 0, measured >= duration * minimumCoverage else { return nil }
        return ConditioningHeartRateSummary(
            averageBPM: Int((weighted / measured).rounded()),
            maxBPM: Int(peak.rounded()),
            zoneSeconds: zones
        )
    }
}
