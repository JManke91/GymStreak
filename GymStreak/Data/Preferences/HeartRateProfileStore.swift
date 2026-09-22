//
//  HeartRateProfileStore.swift
//  GymStreak
//
//  Persists the conditioning heart-rate profile. Same storage as the user's
//  other settings (`WeightUnitPreference`): plain `UserDefaults`, write-through.
//  See docs/fight-conditioning.md.
//

import Foundation
import Observation

@Observable
@MainActor
final class HeartRateProfileStore: HeartRateProfileStoring {

    private static let key = "conditioning.heartRateProfile"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        heartRateProfile = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(HeartRateProfile.self, from: $0) }
    }

    var heartRateProfile: HeartRateProfile? {
        didSet {
            if let heartRateProfile, let data = try? JSONEncoder().encode(heartRateProfile) {
                defaults.set(data, forKey: Self.key)
            } else {
                defaults.removeObject(forKey: Self.key)
            }
            onChange?()
        }
    }
}
