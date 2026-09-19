//
//  HealthSyncPreferenceReading.swift
//  GymStreak
//

import Foundation

/// Whether the user allows GymStreak to write to Apple Health — the same
/// setting the strength path honors.
@MainActor
protocol HealthSyncPreferenceReading: AnyObject {
    var isHealthSyncEnabled: Bool { get }
}
