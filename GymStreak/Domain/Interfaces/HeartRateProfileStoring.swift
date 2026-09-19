//
//  HeartRateProfileStoring.swift
//  GymStreak
//
//  The user's conditioning heart-rate profile, readable and writable.
//  See docs/fight-conditioning.md.
//

import Foundation

/// `@MainActor` for the same reason as `WeightUnitPreferenceProviding`: the
/// conformer is main-actor-isolated state bound straight into SwiftUI.
@MainActor
protocol HeartRateProfileStoring: AnyObject {

    /// `nil` until the user has set up their profile.
    var heartRateProfile: HeartRateProfile? { get set }
}
