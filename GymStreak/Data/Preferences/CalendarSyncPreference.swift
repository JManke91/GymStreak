//
//  CalendarSyncPreference.swift
//  GymStreak
//
//  Persists the "Sync to Apple Calendar" opt-in via UserDefaults. Same shape
//  as WeightUnitPreference: @Observable, write-through in `didSet`.
//  See docs/calendar-sync.md.
//

import Foundation
import Observation

/// The one store of the user's calendar-sync opt-in.
///
/// `@MainActor`: mutable state bound directly into SwiftUI, and a `static let
/// shared` of a non-`Sendable` type is global shared mutable state under strict
/// concurrency. Main-actor isolation makes the class implicitly `Sendable`.
@Observable
@MainActor
final class CalendarSyncPreference: CalendarSyncPreferenceProviding {

    // MARK: - Singleton

    static let shared = CalendarSyncPreference()

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let isEnabled = "calendar_sync.enabled"
    }

    private let defaults: UserDefaults

    // MARK: - Init

    /// Hydrates from `defaults`. Off by default — no key on a fresh install
    /// means the user has never opted in, and `bool(forKey:)` answers `false`
    /// for a missing key, which is exactly the wanted default.
    ///
    /// - Parameter defaults: injectable so the flag can be tested against a
    ///   throwaway suite instead of the device's real defaults.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isCalendarSyncEnabled = defaults.bool(forKey: Keys.isEnabled)
    }

    // MARK: - Stored Properties

    /// Whether the user has switched calendar sync on.
    /// Key: `calendar_sync.enabled`. Default: `false`.
    ///
    /// Written through on every change so the toggle survives relaunch. The
    /// flag is intent only — `WorkoutCalendarSyncing` owns whether the
    /// permission and the calendar are actually in place.
    var isCalendarSyncEnabled: Bool {
        didSet {
            defaults.set(isCalendarSyncEnabled, forKey: Keys.isEnabled)
        }
    }
}
