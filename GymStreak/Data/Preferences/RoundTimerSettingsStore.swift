//
//  RoundTimerSettingsStore.swift
//  GymStreak
//
//  Device-local `UserDefaults`, as JSON: the settings are a convenience, not
//  data, so they need no iCloud mirror (docs/fight-conditioning.md, "Round timer").
//

import Foundation

@MainActor
final class RoundTimerSettingsStore: RoundTimerSettingsStoring {

    private static let key = "roundTimer.lastConfiguration"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastUsedConfiguration: RoundTimerConfiguration? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? Self.decoder.decode(RoundTimerConfiguration.self, from: data)
    }

    func remember(_ configuration: RoundTimerConfiguration) {
        guard let data = try? Self.encoder.encode(configuration) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
