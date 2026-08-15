//
//  LifetimeTotalsAggregator.swift
//  GymStreak
//
//  Reduces every completed session to the three all-time figures §8 placement B
//  shows. See docs/pro-subscription.md §5g.
//

import Foundation

/// Sums completed sessions into `LifetimeTrainingTotals`.
///
/// A pure function over a model array, like `FortschrittAggregator` and
/// `HistorySnapshotBuilder`: isolation-agnostic, so the `@ModelActor` history
/// store can call it from its own executor, and assertable without a container.
enum LifetimeTotalsAggregator {

    /// - Parameter sessions: completed sessions only. This does no filtering —
    ///   the caller's fetch decides what "completed" means, exactly as it does
    ///   for the other history aggregators.
    static func build(sessions: [WorkoutSession]) -> LifetimeTrainingTotals {
        var completedSets = 0
        var volume = 0.0
        for session in sessions {
            // One traversal per session: reading `completedSetsCount` and
            // `totalVolume` separately walks the relationship graph twice
            // (docs/history-performance.md).
            let aggregates = session.aggregates
            completedSets += aggregates.completedSets
            volume += aggregates.volume
        }
        return LifetimeTrainingTotals(
            workoutCount: sessions.count,
            completedSetCount: completedSets,
            volumeKilograms: volume
        )
    }
}
