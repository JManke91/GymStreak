//
//  ExerciseDeepDiveFactProviding.swift
//  GymStreak
//
//  The read boundary behind the exercise detail screen's AI Coach narrative.
//  See docs/ai-coach.md §3.
//

import Foundation

/// Answers the two questions the exercise deep-dive asks of workout history — *has the
/// described body of work changed?* and *what does it say?* — without exposing any
/// `PersistentModel`.
///
/// A boundary of its own rather than another requirement on `HistorySnapshotProviding`,
/// for the reason `LifetimeTrainingTotalsProviding` gives: this is a different question
/// (an AI prompt input, not a screen's read model) with a different consumer, and the
/// History protocol's requirements each exist for one screen. The **same concrete type**
/// conforms to both, so there is still exactly one `@ModelActor` and one `ModelContext`
/// warming the completed-session graph — and here that is not merely economical: the
/// chart directly above the narrative is served by that same actor from that same graph,
/// so a second context would fault every session twice for one screen.
///
/// ⚠️ Like `HistorySnapshotProviding`, **the off-main guarantee is not provided here.**
/// Under `SWIFT_APPROACHABLE_CONCURRENCY` (SE-0461) a plain `nonisolated async`
/// requirement runs on the *caller's* actor, and both calls below fetch all of completed
/// history and fault its relationships — exactly the shape that produced the hang in
/// `docs/history-performance.md`. The guarantee lives on the conforming type: any
/// conformer that does real work must carry `@concurrent` on its own method. See
/// `docs/swift6-concurrency.md` §1.
///
/// Neither call throws. A failed fetch degrades to "nothing found" — no cache key, no
/// narrative — because that is already the user-visible outcome of an empty history, and
/// it is the behaviour the `try?`-based aggregator this replaced always had.
protocol ExerciseDeepDiveFactProviding: Sendable {

    /// The timestamp the cached narrative for this (exercise, usage) is stamped with, or
    /// `nil` when the usage has no completed set.
    ///
    /// Separate from `fetchDeepDiveAggregate` on purpose, and cheap on purpose. It runs
    /// from the screen's `.task` — on appear and on every exercise or usage switch —
    /// only to ask whether a cached narrative exists, so it must answer without
    /// materializing the whole workout graph. Answering it with the aggregate would put a
    /// full-history walk in front of the chart load happening on the same screen at the
    /// same moment, on the same model actor.
    func fetchDeepDiveCacheTimestamp(
        exerciseId: UUID,
        usageSelection: ExerciseUsageSelection
    ) async -> Date?

    /// The narrative's input **and** its cache timestamp, from one walk of history.
    ///
    /// Called only when a generation is already admitted — never to decide whether one
    /// should be.
    ///
    /// - Parameters:
    ///   - exerciseId: id of the live library exercise the screen is showing.
    ///   - exerciseName: that same entry's name. Handed down rather than re-derived, so
    ///     the identity rule sees the exercise the user is looking at even where two
    ///     library entries share a name.
    ///   - usage: the usage the screen is showing — selection and picker label together.
    ///   - locale: the reader's locale, which the input's month labels are written in.
    ///   - weightUnit: the reader's weight unit. It reaches the aggregate because the
    ///     segment magnitudes are *rendered* there, as text — everything that stays a
    ///     number stays canonical kilograms. See docs/weight-unit-preference.md §13.
    func fetchDeepDiveAggregate(
        exerciseId: UUID,
        exerciseName: String,
        usage: DeepDiveUsage,
        locale: Locale,
        weightUnit: WeightUnit
    ) async -> ExerciseDeepDiveAggregate
}
