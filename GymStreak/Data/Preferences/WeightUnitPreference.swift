//
//  WeightUnitPreference.swift
//  GymStreak
//
//  Persists the user's weight unit via UserDefaults. Same shape as
//  AICoachPreferences: @Observable, write-through in `didSet`.
//

import Foundation
import Observation

/// The one store of the user's weight unit.
///
/// `@MainActor`: mutable state bound directly into SwiftUI, and a `static let
/// shared` of a non-`Sendable` type is global shared mutable state under strict
/// concurrency. Main-actor isolation makes the class implicitly `Sendable`.
@Observable
@MainActor
final class WeightUnitPreference: WeightUnitPreferenceProviding {

    // MARK: - Singleton

    static let shared = WeightUnitPreference()

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let weightUnit = "units.weight"
    }

    private let defaults: UserDefaults

    // MARK: - Init

    /// Hydrates from `defaults`, seeding the locale default on the very first
    /// launch — and only then. The seed is written back immediately, so from the
    /// second launch on there is a stored value and the locale is never
    /// consulted again: the unit is the user's from that point, and a trip
    /// abroad or a system-region change must not move it.
    ///
    /// - Parameters are injectable so the seeding rule can be tested against a
    ///   throwaway suite instead of the device's real defaults.
    init(defaults: UserDefaults = .standard, locale: Locale = .current) {
        self.defaults = defaults
        if let stored = defaults.string(forKey: Keys.weightUnit),
           let unit = WeightUnit(rawValue: stored) {
            weightUnit = unit
        } else {
            let seeded = WeightUnit.default(for: locale)
            weightUnit = seeded
            // Assigning in `init` does not run `didSet`, so the seed is written
            // here — that write is what makes this a one-time decision.
            defaults.set(seeded.rawValue, forKey: Keys.weightUnit)
        }
    }

    // MARK: - Stored Properties

    /// The unit weights are shown and entered in.
    /// Key: `units.weight`. Default: seeded from the locale on first launch.
    var weightUnit: WeightUnit {
        didSet {
            defaults.set(weightUnit.rawValue, forKey: Keys.weightUnit)
            onChange?(weightUnit)
        }
    }

    /// Called after a change has been written through. The composition root
    /// uses it to push the new unit to the watch, which has no other way to
    /// learn of it — the App Group suite is shared within a device's app
    /// family, not between iPhone and Watch (see docs/watch-sync.md).
    ///
    /// A plain callback rather than an `@Observable` read: this fires on the
    /// write, so nothing has to poll or diff. Not invoked for the first-launch
    /// locale seed, which happens in `init` and therefore runs no `didSet` —
    /// correct, since the composition root reads the seeded value directly.
    ///
    /// `@ObservationIgnored` because this is wiring, not UI state: nothing
    /// renders it, so it needs no observation accessors.
    @ObservationIgnored var onChange: ((WeightUnit) -> Void)?
}
