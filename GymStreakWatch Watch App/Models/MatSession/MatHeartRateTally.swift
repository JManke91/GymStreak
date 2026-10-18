//
//  MatHeartRateTally.swift
//  GymStreakWatch Watch App
//
//  The heart-rate side of a mat session recorded on the watch (positioning
//  ticket 05, docs/fight-conditioning.md "Mat sessions on the watch"): average,
//  maximum and time per intensity band from the live samples, and the
//  suggested intensity derived from that time. Pure logic.
//

import Foundation

/// The iPhone's `MatSport` raw values — the same list the iPhone logs.
enum WatchMatSport: String, CaseIterable, Codable, Identifiable {
    case bjj, mma, muayThai, boxing, wrestling, other

    var id: String { rawValue }
}

/// The iPhone's `MatIntensity` raw values.
enum WatchMatIntensity: String, CaseIterable, Codable, Identifiable {
    case drilling, moderate, hardSparring

    var id: String { rawValue }
}

/// Heart-rate samples folded into session time. Each sample's value holds until the
/// next one arrives, capped at `maximumGap` so a sensor dropout (or a crash) is not
/// counted as minutes at the last value. Times are session time (pauses excluded).
struct MatHeartRateTally: Codable, Equatable {
    static let maximumGap: TimeInterval = 15

    private(set) var measuredSeconds: TimeInterval = 0
    private(set) var moderateSeconds: TimeInterval = 0
    private(set) var hardSeconds: TimeInterval = 0
    private(set) var maximum: Int?
    private var weightedSum: Double = 0
    private var last: Sample?

    private struct Sample: Codable, Equatable {
        let bpm: Int
        let elapsed: TimeInterval
    }

    /// Time-weighted; the single value when only one sample arrived.
    var average: Int? {
        guard measuredSeconds > 0 else { return last?.bpm }
        return Int((weightedSum / measuredSeconds).rounded())
    }

    /// Without `zones` only the average and maximum are kept.
    mutating func record(_ bpm: Int, at elapsed: TimeInterval, zones: WatchMatIntensityZones?) {
        close(at: elapsed, zones: zones)
        last = Sample(bpm: bpm, elapsed: elapsed)
        maximum = max(maximum ?? bpm, bpm)
    }

    /// Credits the last sample up to `elapsed` — on every sample and when the session
    /// ends. Calling it twice for the same moment adds nothing.
    mutating func close(at elapsed: TimeInterval, zones: WatchMatIntensityZones?) {
        guard let last else { return }
        let span = min(max(0, elapsed - last.elapsed), Self.maximumGap)
        measuredSeconds += span
        weightedSum += Double(last.bpm) * span
        if let zones {
            if last.bpm >= zones.hardFromBPM {
                hardSeconds += span
            } else if last.bpm >= zones.moderateFromBPM {
                moderateSeconds += span
            }
        }
        self.last = Sample(bpm: last.bpm, elapsed: max(elapsed, last.elapsed))
    }
}

/// The documented zone-time rule. Shares of *measured* time, so a dropout or a
/// crash-recovery gap shifts nothing:
///   - at least 20 % at or above the hard threshold → hard sparring
///   - else at least 40 % above the aerobic zone (moderate or hard) → moderate
///   - else → drilling
/// No suggestion without zones (no heart-rate profile, or RPE only) or with less
/// than 5 minutes of heart rate — the user picks.
enum MatIntensitySuggestion {
    static let minimumMeasured: TimeInterval = 5 * 60
    static let hardShare = 0.20
    static let moderateShare = 0.40

    static func suggest(from tally: MatHeartRateTally, zones: WatchMatIntensityZones?) -> WatchMatIntensity? {
        guard zones != nil, tally.measuredSeconds >= minimumMeasured else { return nil }
        let hard = tally.hardSeconds / tally.measuredSeconds
        let aboveAerobic = (tally.moderateSeconds + tally.hardSeconds) / tally.measuredSeconds
        if hard >= hardShare { return .hardSparring }
        if aboveAerobic >= moderateShare { return .moderate }
        return .drilling
    }
}
