//
//  PersonalBestsProviding.swift
//  GymStreak
//
//  The read boundary behind the share card's PRs. See docs/workout-sharing.md.
//

import Foundation

/// Answers "what is this user's best estimated 1RM per exercise, before a given workout?"
/// without exposing any `PersistentModel`.
///
/// The completion screen shares a workout that is **not saved yet**, and a model actor cannot
/// be trusted to see a session the main context has not committed (docs/workout-summary.md).
/// So the history walk happens here, off the main actor, and the caller checks its in-memory
/// session against the result with `PersonalRecordService.records(in:priorBests:)`.
///
/// A boundary of its own rather than a requirement on `HistorySnapshotProviding`, for the
/// reason `LifetimeTrainingTotalsProviding` gives; the same concrete type conforms to both.
///
/// ⚠️ The off-main guarantee is not provided here. A conformer that does real work must carry
/// `@concurrent` on its own method — see `docs/swift6-concurrency.md` §1.
protocol PersonalBestsProviding: Sendable {

    /// Best estimated 1RM per `WorkoutExercise.stableKey` over the completed sessions that
    /// started before `date`, ignoring `excludedSessionID`.
    func fetchPersonalBests(before date: Date, excludingSessionID: UUID) async throws -> [String: Double]
}
