//
//  ActiveWorkoutRegistry.swift
//  GymStreak
//
//  Holds the app-wide "a workout is in progress" flag.
//  See docs/pro-subscription.md.
//

import Foundation

/// The one place the app records that a workout session is running.
///
/// Deliberately dumb and deliberately not `@Observable`: nothing renders from
/// it. Its only reader is `PaywallPresenter`, which asks at the instant a
/// paywall is requested, so there is no state for SwiftUI to track.
///
/// Only one workout can be active at a time app-wide, so a plain boolean is
/// enough — no counting, no session identity.
@MainActor
final class ActiveWorkoutRegistry: ActiveWorkoutReporting {

    private(set) var isWorkoutActive = false

    func setWorkoutActive(_ isActive: Bool) {
        isWorkoutActive = isActive
    }
}
