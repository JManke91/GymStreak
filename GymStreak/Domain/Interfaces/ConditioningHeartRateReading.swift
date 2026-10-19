//
//  ConditioningHeartRateReading.swift
//  GymStreak
//
//  Read-only Apple Health gateway for the heart rate of a finished conditioning
//  session's time window. See docs/workout-sharing.md.
//

import Foundation

@MainActor
protocol ConditioningHeartRateReading: AnyObject {

    /// Every heart-rate reading between `start` and `end`, from any source — an
    /// iPhone-run session with a watch on the wrist has its readings outside the
    /// workout. Never throws: denied access and no data look the same in HealthKit,
    /// and both mean the card's no-heart-rate state.
    func readings(from start: Date, to end: Date) async -> [HeartRateReading]
}
