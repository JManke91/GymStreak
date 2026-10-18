//
//  WatchRoundTimerSettingsStore.swift
//  GymStreakWatch Watch App
//
//  The round timer's last-used settings on this watch (positioning ticket 07,
//  docs/fight-conditioning.md "Round timer"). Per device and never synced: the
//  watch runs its own rounds without the iPhone.
//

import Foundation

@MainActor
final class WatchRoundTimerSettingsStore {
    static let key = "roundTimer.lastConfiguration"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The last configuration started, or the default (BJJ, 6 rounds) the first time.
    func load() -> RoundTimerConfiguration {
        guard let data = defaults.data(forKey: Self.key),
              let configuration = try? Self.decoder.decode(RoundTimerConfiguration.self, from: data)
        else { return .default }
        return configuration
    }

    func save(_ configuration: RoundTimerConfiguration) {
        guard let data = try? Self.encoder.encode(configuration) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
