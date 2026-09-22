//
//  ConditioningZoneGauge.swift
//  GymStreakWatch Watch App
//
//  Where a heart rate sits on the runner's zone gauge (docs/fight-conditioning.md,
//  watch runner redesign). The gauge spans the personal range plus a fixed margin
//  either side, so the target band always sits in the middle third and a drift is
//  visible before it becomes large. Pure, unit-tested.
//

import Foundation

enum ConditioningZoneGauge {
    /// bpm shown below the lower and above the upper bound.
    static let margin = 40

    /// 0 = the gauge's start, 1 = its end; clamped, so an extreme reading pins
    /// the marker to the end rather than leaving the gauge.
    static func fraction(of bpm: Int, in zone: WatchHeartRateZone) -> Double {
        let lower = Double(zone.lowerBPM - margin)
        let upper = Double(zone.upperBPM + margin)
        return min(1, max(0, (Double(bpm) - lower) / (upper - lower)))
    }

    static func band(of zone: WatchHeartRateZone) -> ClosedRange<Double> {
        fraction(of: zone.lowerBPM, in: zone)...fraction(of: zone.upperBPM, in: zone)
    }

    /// bpm between the reading and the nearer bound; 0 inside the range.
    static func distance(of bpm: Int, from zone: WatchHeartRateZone) -> Int {
        if bpm < zone.lowerBPM { return zone.lowerBPM - bpm }
        if bpm > zone.upperBPM { return bpm - zone.upperBPM }
        return 0
    }
}
