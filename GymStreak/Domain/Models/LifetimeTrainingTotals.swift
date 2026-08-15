//
//  LifetimeTrainingTotals.swift
//  GymStreak
//
//  Everything the user has logged, reduced to three numbers.
//  See docs/pro-subscription.md §5g.
//

import Foundation

/// All-time training totals across every completed workout.
///
/// Built for §8 placement B — the endowed-progress paywall reads
/// "You've logged N workouts, X sets, Y kg of volume" — but it is an ordinary
/// history aggregate, not a monetization type: it lives here rather than in
/// `Domain/Models/Pro/` so any later surface (a year-in-review, a profile
/// header) can read the same numbers instead of re-deriving them.
///
/// **These figures are the whole persuasive content of placement B**, so they
/// are computed from the same `WorkoutSession.aggregates` traversal the History
/// list uses — an off-by-one total on that screen does more damage than showing
/// nothing at all.
struct LifetimeTrainingTotals: Equatable, Sendable {

    /// Completed workout sessions.
    let workoutCount: Int

    /// Sets the user actually **completed**, not sets that were planned. A
    /// planned-but-skipped set is not something anyone logged.
    let completedSetCount: Int

    /// Total volume in kilograms, summed with the one volume formula in the app
    /// (`WorkoutSession.aggregates`).
    let volumeKilograms: Double

    static let empty = LifetimeTrainingTotals(
        workoutCount: 0,
        completedSetCount: 0,
        volumeKilograms: 0
    )
}
