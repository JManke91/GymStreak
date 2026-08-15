//
//  LifetimeTrainingTotalsProviding.swift
//  GymStreak
//
//  The read boundary behind §8 placement B's endowed figures.
//  See docs/pro-subscription.md §5g.
//

import Foundation

/// Answers "what has this user logged, all time?" without exposing any
/// `PersistentModel`.
///
/// A boundary of its own rather than a sixth requirement on
/// `HistorySnapshotProviding`: this is a different question (three all-time
/// scalars, not a screen's read model) with a different consumer, and the
/// History protocol's five requirements each exist for one screen. The **same
/// concrete type** conforms to both, so there is still exactly one
/// `@ModelActor` and one `ModelContext` warming the completed-session graph —
/// which is the constraint that argued against a second boundary in the first
/// place.
///
/// ⚠️ Like `HistorySnapshotProviding`, **the off-main guarantee is not provided
/// here.** Under `SWIFT_APPROACHABLE_CONCURRENCY` (SE-0461) a plain
/// `nonisolated async` requirement runs on the *caller's* actor, and this
/// aggregation walks every completed session's relationship graph — exactly the
/// shape that produced the hang in `docs/history-performance.md`. The guarantee
/// lives on the conforming type: any conformer that does real work must carry
/// `@concurrent` on its own method. See `docs/swift6-concurrency.md` §1.
protocol LifetimeTrainingTotalsProviding: Sendable {

    /// How many completed sessions exist, and nothing else.
    ///
    /// Separate from `fetchLifetimeTotals()` on purpose. §8 B's trigger asks
    /// this after **every** completed workout, including the ones that provably
    /// cannot meet the threshold, so it has to be a counting query rather than
    /// an aggregation: a conformer must answer without materializing sessions or
    /// faulting a relationship. Answering it with the full read would put a
    /// whole-history walk in front of the History tab's own post-workout
    /// refetch, which shares the same model actor.
    func fetchCompletedWorkoutCount() async throws -> Int

    /// Totals over every completed session. Never filtered by date — placement
    /// B's persuasion is that the numbers are the user's *whole* history.
    ///
    /// Called only when placement B is about to be shown, never to decide
    /// whether it should be.
    func fetchLifetimeTotals() async throws -> LifetimeTrainingTotals
}
