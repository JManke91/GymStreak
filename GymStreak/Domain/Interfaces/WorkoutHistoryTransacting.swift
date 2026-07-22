//
//  WorkoutHistoryTransacting.swift
//  GymStreak
//
//  Narrow Domain factory for isolated history transactions (ticket 04,
//  in-workout routine editing). Watch-workout ingestion must commit exactly
//  once into a context that carries none of the app's unrelated dirty
//  main-context work — deferring that work rather than saving or rolling it
//  back. Domain stays free of ModelContext and concrete Watch DTOs; the Data
//  layer implements this with a fresh autosave-disabled context per
//  transaction (see SwiftDataWorkoutHistoryTransaction).
//

import Foundation

@MainActor
protocol WorkoutHistoryTransacting: AnyObject {
    /// A fresh, isolated transaction. Nothing done through its repositories
    /// reaches the store until their single explicit `save()`.
    func makeIsolatedTransaction() -> WorkoutHistoryTransaction
}

/// Repositories bound to one isolated context. Calling `save()` on either
/// repository commits that context exactly once; `rollback()` discards its
/// uncommitted changes without touching any other context's state.
@MainActor
protocol WorkoutHistoryTransaction: AnyObject {
    var routineRepository: RoutineRepository { get }
    var workoutSessionRepository: WorkoutSessionRepository { get }
    func rollback()
}
