//
//  HeartRateProfileHealthReading.swift
//  GymStreak
//
//  Read-only Apple Health gateway that pre-fills the heart-rate profile.
//  See docs/fight-conditioning.md.
//

import Foundation

@MainActor
protocol HeartRateProfileHealthReading: AnyObject {

    var isHealthDataAvailable: Bool { get }

    /// Asks for read access to date of birth and resting heart rate (the system
    /// only prompts for types not decided yet), then reads both. Never throws:
    /// a denied read and an empty one look the same, so both come back as `nil`.
    func readPrefill() async -> HeartRateHealthPrefill
}
