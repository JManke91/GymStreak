//
//  ActiveWorkoutReporting.swift
//  GymStreak
//
//  Whether a workout session is running right now, app-wide. Exists so Rule 3
//  (no upsell inside a workout) can be enforced in one place.
//  See docs/pro-subscription.md.
//

import Foundation

/// The app-wide "a workout is in progress" signal.
///
/// There are two `WorkoutViewModel` instances (one on Routines, one on History)
/// and each owns its own HealthKit session, so no single ViewModel can answer
/// this question for the app. This is that answer, held once and injected.
///
/// One protocol with both the read and the write rather than a reader/writer
/// pair: it carries a single boolean, has one conformer, and splitting it would
/// double the composition-root wiring for no added safety.
@MainActor
protocol ActiveWorkoutReporting: AnyObject {

    /// `true` from the moment a workout session starts until it is finished or
    /// discarded.
    var isWorkoutActive: Bool { get }

    /// Reported by the owner of the workout session as it starts and ends.
    func setWorkoutActive(_ isActive: Bool)
}
