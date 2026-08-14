//
//  CompletedSessionFetch.swift
//  GymStreak
//

import Foundation
import SwiftData

/// The one prefetch-correct way to load the whole completed-workout graph.
///
/// Extracted from `SwiftDataHistorySnapshotStore` (audit P1.3) so the AI-coach fact
/// actor reuses this exact fetch ordering instead of making the same undocumented
/// bet independently — `docs/swift6-concurrency.md` §1 states that rule, because the
/// two-step warm-up below relies on `ModelContext`'s identity map, which Apple does
/// not document. One shared helper means one place to re-measure if that bet ever
/// stops paying.
///
/// **Call this only from inside a model actor.** It is synchronous and unbounded: it
/// fetches every completed session and faults in every exercise and set. On the main
/// actor that is the ~600 ms hang in `docs/history-performance.md`.
enum CompletedSessionFetch {

    /// Every completed session, newest first, with `workoutExercises`, their `sets` and
    /// the owning `routine` already registered in `context`.
    ///
    /// `\.routine` joined the session prefetch for audit P1.6, whose resolver compares
    /// `session.routine?.id` per candidate session. It is a to-one hop onto a small table
    /// that `fetchTrainingSnapshot` fetches in full anyway, so it is cheaper than adding
    /// a second variant of this fetch — and leaving it out would have reintroduced a
    /// per-session fault, the thing this helper exists to prevent.
    static func withFullGraph(in context: ModelContext) throws -> [WorkoutSession] {
        // Fetching the child entity directly is the only way to prefetch the second to-many hop:
        // `WorkoutSession.workoutExercises` is a collection, so a key path cannot continue to
        // `.sets`. Registering the graph in this context prevents a set fault per exercise later.
        var exerciseDescriptor = FetchDescriptor<WorkoutExercise>(
            predicate: #Predicate { exercise in
                exercise.workoutSession?.endTime != nil
            }
        )
        exerciseDescriptor.relationshipKeyPathsForPrefetching = [\.sets, \.workoutSession]
        _ = try context.fetch(exerciseDescriptor)

        var sessionDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.endTime != nil
            },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        sessionDescriptor.relationshipKeyPathsForPrefetching = [\.workoutExercises, \.routine]
        return try context.fetch(sessionDescriptor)
    }

    /// Every completed session, newest first, with only the owning `routine` prefetched.
    ///
    /// For callers that date routines against their last completion and never touch a
    /// set — `withFullGraph` would fault the entire exercise/set graph for nothing.
    /// A single direct relationship key path is the documented use of
    /// `relationshipKeyPathsForPrefetching`, so this makes none of the bets above.
    static func withRoutine(in context: ModelContext) throws -> [WorkoutSession] {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.endTime != nil
            },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.routine]
        return try context.fetch(descriptor)
    }
}
