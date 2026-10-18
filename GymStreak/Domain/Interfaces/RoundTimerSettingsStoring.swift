//
//  RoundTimerSettingsStoring.swift
//  GymStreak
//
//  The round timer remembers the last settings it ran with — per device, like
//  the conditioning safety flag (docs/fight-conditioning.md, "Round timer").
//

import Foundation

@MainActor
protocol RoundTimerSettingsStoring: AnyObject {
    /// `nil` on a device that has never run the timer.
    var lastUsedConfiguration: RoundTimerConfiguration? { get }
    func remember(_ configuration: RoundTimerConfiguration)
}
