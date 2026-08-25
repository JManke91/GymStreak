//
//  LegacyHistoryAttributing.swift
//  GymStreak
//

import Foundation

/// Write boundary for resolving legacy workout history that cannot be attributed to a
/// library exercise by name alone.
///
/// Separate from `HistorySnapshotProviding` deliberately — that one is documented as a
/// **read** boundary over the completed-session graph, and this is the only place in the
/// app that writes to history outside of recording a workout.
///
/// What it may change is deliberately tiny. Workout history is denormalised on purpose so
/// it survives routine and exercise edits: `exerciseName`, `muscleGroups` and
/// `loadBehaviorRaw` are a snapshot of what the user actually performed, and re-deriving
/// them from today's library would change what an old session *means*. Attribution sets
/// the missing `exerciseId` link and nothing else.
///
/// ⚠️ Like `HistorySnapshotProviding`, this protocol does **not** provide the off-main
/// guarantee: under SE-0461 a plain `nonisolated async` requirement runs on the caller's
/// actor. The conforming type carries `@concurrent` on its own method. See
/// `docs/swift6-concurrency.md` §1.
protocol LegacyHistoryAttributing: Sendable {
    /// Links every workout row named `exerciseName` that carries no `exerciseId` to
    /// `exerciseId`.
    ///
    /// Idempotent by construction: a row that already has an `exerciseId` is never
    /// touched, so re-running this can neither move an attributed row nor overwrite one
    /// the user resolved differently.
    ///
    /// - Parameters:
    ///   - exerciseName: matched case-insensitively against the row's denormalised name —
    ///     the same rule `ExerciseProgressAggregator.isUnattributedLegacyRow` applies when
    ///     it decides what to report as missing.
    ///   - exerciseId: the live library exercise the user chose. Only the user knows
    ///     whether a 2025 "Biceps Curls" was the barbell or the dumbbell, so nothing here
    ///     may guess.
    /// - Returns: how many rows were linked. Zero means there was nothing left to resolve.
    func attributeLegacyRows(
        named exerciseName: String,
        to exerciseId: UUID
    ) async throws -> Int
}
