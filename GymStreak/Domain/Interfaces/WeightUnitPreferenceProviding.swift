//
//  WeightUnitPreferenceProviding.swift
//  GymStreak
//
//  Protocol surface for the user's weight-unit choice, so Presentation depends
//  on an abstraction rather than the `WeightUnitPreference` singleton.
//

import Foundation

/// The user's displayed weight unit, readable and writable.
///
/// `@MainActor` for the same reason as `AICoachPreferencesProviding`: the only
/// conformer is main-actor-isolated mutable state bound straight into SwiftUI,
/// and a nonisolated protocol would make that conformance an isolation mismatch
/// under strict concurrency.
@MainActor
protocol WeightUnitPreferenceProviding: AnyObject {

    /// The unit weights are shown and entered in. Kilograms stay the stored
    /// unit whatever this says — see `WeightUnit`.
    var weightUnit: WeightUnit { get set }
}
