//
//  HeartRateProfile.swift
//  GymStreak
//
//  The user's heart-rate profile for conditioning targets, and the personal
//  target it produces. The math lives in `HeartRateZones`.
//  See docs/fight-conditioning.md.
//

import Foundation

/// What the user told us about their heart rate.
///
/// Age and measured maximum are both kept whichever source is active, so
/// switching the source back and forth never loses what the user typed.
struct HeartRateProfile: Codable, Equatable, Sendable {

    enum MaxHeartRateSource: String, Codable, Sendable {
        /// HRmax ≈ 208 − 0.7 × age (Tanaka) — an estimate, ± ~10 bpm.
        case estimatedFromAge
        /// A maximum the user measured themselves.
        case measured
    }

    var maxSource: MaxHeartRateSource
    var age: Int?
    var measuredMaxHeartRate: Int?
    /// Optional; when present the zone uses heart-rate reserve (Karvonen).
    var restingHeartRate: Int?
    /// Beta-blockers and similar: heart-rate targets are off, RPE only.
    var usesHeartRateMedication: Bool

    init(
        maxSource: MaxHeartRateSource = .estimatedFromAge,
        age: Int? = nil,
        measuredMaxHeartRate: Int? = nil,
        restingHeartRate: Int? = nil,
        usesHeartRateMedication: Bool = false
    ) {
        self.maxSource = maxSource
        self.age = age
        self.measuredMaxHeartRate = measuredMaxHeartRate
        self.restingHeartRate = restingHeartRate
        self.usesHeartRateMedication = usesHeartRateMedication
    }
}

/// A personal heart-rate range for one effort.
struct HeartRateTarget: Equatable, Sendable {

    enum Method: Equatable, Sendable {
        /// Percent of maximum heart rate.
        case percentOfMax
        /// Percent of heart-rate reserve (max − resting), added to resting — Karvonen.
        case heartRateReserve
    }

    let lowerBPM: Int
    let upperBPM: Int
    let lowerPercent: Int
    let upperPercent: Int
    let method: Method
    /// The maximum the range is built on was estimated from age, not measured.
    let isMaxEstimated: Bool
}

/// Values read from Apple Health to pre-fill the profile. Any may be missing:
/// nothing recorded, or read access denied — HealthKit does not say which.
struct HeartRateHealthPrefill: Equatable, Sendable {
    let age: Int?
    let restingHeartRate: Int?
    /// The highest heart rate recorded in the last `HeartRateZones.peakLookbackMonths`.
    /// Only ever *suggested* as a measured max: everyday training rarely reaches the
    /// true maximum, and one optical-sensor spike can overshoot it.
    let peakHeartRate: Int?

    init(age: Int?, restingHeartRate: Int?, peakHeartRate: Int? = nil) {
        self.age = age
        self.restingHeartRate = restingHeartRate
        self.peakHeartRate = peakHeartRate
    }
}
