//
//  UserDefaultsHealthSyncPreference.swift
//  GymStreak
//

import Foundation

/// The strength path's Health-sync switch (`WorkoutViewModel`), read for the
/// conditioning save.
@MainActor
final class UserDefaultsHealthSyncPreference: HealthSyncPreferenceReading {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Shared with `WorkoutViewModel`, which owns the toggle.
    static let key = "healthKitSyncEnabled"
    static let defaultValue = true

    var isHealthSyncEnabled: Bool {
        defaults.object(forKey: Self.key) as? Bool ?? Self.defaultValue
    }
}
