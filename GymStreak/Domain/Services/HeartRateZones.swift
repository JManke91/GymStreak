//
//  HeartRateZones.swift
//  GymStreak
//
//  Personal heart-rate targets for conditioning: HRmax estimate, % HRmax,
//  Karvonen (% heart-rate reserve) and plausibility checks. Pure logic.
//  See docs/fight-conditioning.md ("Corrected default protocol").
//

import Foundation

enum HeartRateZones {

    enum ValidationIssue: Equatable, Sendable {
        case missingAge
        case ageOutOfRange
        case missingMaxHeartRate
        case maxHeartRateOutOfRange
        case restingHeartRateOutOfRange
        /// Resting too close to max for a meaningful reserve.
        case restingTooCloseToMax
    }

    static let ageRange = 13...100
    static let maxHeartRateRange = 120...230
    static let restingHeartRateRange = 30...120
    /// Below this reserve (max − resting) the input is implausible.
    static let minimumReserve = 40
    /// The population spread of the age estimate, shown next to it.
    static let estimateUncertainty = 10
    /// How far back the Apple Health peak suggestion looks.
    static let peakLookbackMonths = 6

    /// Aerobic zone: 60–75 % of HRmax, or 50–70 % of heart-rate reserve.
    static let aerobicPercentOfMax = 60...75
    static let aerobicPercentOfReserve = 50...70

    /// Tanaka: HRmax ≈ 208 − 0.7 × age.
    static func estimatedMaxHeartRate(age: Int) -> Int {
        Int((208 - 0.7 * Double(age)).rounded())
    }

    /// Everything wrong with `profile`. Empty means usable. A user on
    /// heart-rate medication needs no numbers at all.
    static func validate(_ profile: HeartRateProfile) -> [ValidationIssue] {
        guard !profile.usesHeartRateMedication else { return [] }
        var issues: [ValidationIssue] = []

        switch profile.maxSource {
        case .estimatedFromAge:
            if let age = profile.age {
                if !ageRange.contains(age) { issues.append(.ageOutOfRange) }
            } else {
                issues.append(.missingAge)
            }
        case .measured:
            if let max = profile.measuredMaxHeartRate {
                if !maxHeartRateRange.contains(max) { issues.append(.maxHeartRateOutOfRange) }
            } else {
                issues.append(.missingMaxHeartRate)
            }
        }

        if let resting = profile.restingHeartRate {
            if !restingHeartRateRange.contains(resting) {
                issues.append(.restingHeartRateOutOfRange)
            } else if issues.isEmpty, let max = maxHeartRate(for: profile), max - resting < minimumReserve {
                issues.append(.restingTooCloseToMax)
            }
        }
        return issues
    }

    /// The maximum the zones are built on, from the active source; `nil` when
    /// that source's value is missing.
    static func maxHeartRate(for profile: HeartRateProfile) -> Int? {
        switch profile.maxSource {
        case .estimatedFromAge: profile.age.map(estimatedMaxHeartRate(age:))
        case .measured: profile.measuredMaxHeartRate
        }
    }

    /// The steady-state aerobic range. `nil` without a profile, with an
    /// invalid one, or for a user on heart-rate medication.
    static func aerobicTarget(for profile: HeartRateProfile?) -> HeartRateTarget? {
        guard let profile, !profile.usesHeartRateMedication, validate(profile).isEmpty,
              let max = maxHeartRate(for: profile) else { return nil }
        let isEstimated = profile.maxSource == .estimatedFromAge

        if let resting = profile.restingHeartRate {
            let percent = aerobicPercentOfReserve
            return HeartRateTarget(
                lowerBPM: karvonen(percent.lowerBound, max: max, resting: resting),
                upperBPM: karvonen(percent.upperBound, max: max, resting: resting),
                lowerPercent: percent.lowerBound,
                upperPercent: percent.upperBound,
                method: .heartRateReserve,
                isMaxEstimated: isEstimated
            )
        }
        let percent = aerobicPercentOfMax
        return HeartRateTarget(
            lowerBPM: Int((Double(max * percent.lowerBound) / 100).rounded()),
            upperBPM: Int((Double(max * percent.upperBound) / 100).rounded()),
            lowerPercent: percent.lowerBound,
            upperPercent: percent.upperBound,
            method: .percentOfMax,
            isMaxEstimated: isEstimated
        )
    }

    /// The heart-rate target for one effort. Only the conversational aerobic
    /// effort has one: interval heart rate lags the effort too much to steer by,
    /// and alactic work is cued by maximal intent, never by heart rate.
    static func target(for effort: ConditioningEffort, profile: HeartRateProfile?) -> HeartRateTarget? {
        effort == .conversational ? aerobicTarget(for: profile) : nil
    }

    /// resting + percent × (max − resting).
    private static func karvonen(_ percent: Int, max: Int, resting: Int) -> Int {
        resting + Int((Double((max - resting) * percent) / 100).rounded())
    }
}
