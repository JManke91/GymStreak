//
//  SwiftDataWorkoutHistoryTransaction.swift
//  GymStreak
//
//  Data implementation of the Domain's isolated history transaction
//  (ticket 04, in-workout routine editing): each transaction is a fresh
//  ModelContext on the shared container with autosave disabled, so watch
//  ingestion commits in exactly one explicit save() and can never save or
//  roll back unrelated dirty main-context work. Consumers that require an
//  immediately authoritative post-save read use a fresh read context and map
//  to immutable values instead of relying on another context's model cache.
//

import Foundation
import SwiftData

@MainActor
final class SwiftDataWorkoutHistoryTransactionFactory: WorkoutHistoryTransacting {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func makeIsolatedTransaction() -> WorkoutHistoryTransaction {
        SwiftDataWorkoutHistoryTransaction(container: container)
    }
}

@MainActor
final class SwiftDataWorkoutHistoryTransaction: WorkoutHistoryTransaction {
    let routineRepository: RoutineRepository
    let workoutSessionRepository: WorkoutSessionRepository
    let exerciseRepository: ExerciseRepository
    private let context: ModelContext

    init(container: ModelContainer) {
        let context = ModelContext(container)
        // Isolated single-commit semantics: nothing reaches the store until
        // the ingestion's one explicit repository save().
        context.autosaveEnabled = false
        self.context = context
        self.routineRepository = SwiftDataRoutineRepository(modelContext: context)
        self.workoutSessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        self.exerciseRepository = SwiftDataExerciseRepository(modelContext: context)
    }

    func rollback() {
        context.rollback()
    }
}
