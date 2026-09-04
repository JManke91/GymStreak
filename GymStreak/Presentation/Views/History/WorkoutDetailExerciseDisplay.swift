//
//  WorkoutDetailExerciseDisplay.swift
//  GymStreak
//
//  Value structs the workout-history detail blocks render from. Everything is
//  resolved once, where the screen builds the rest of its display state, so no
//  block body walks a SwiftData relationship (`setsList`) or reads a `@Model`
//  property — see the main-thread rules in CLAUDE.md.
//

import Foundation

/// One exercise of a recorded session as its history block draws it.
///
/// `sets` already carries the values that block shows: an exercise whose
/// progressive overload was applied displays the *planned* pair, because that
/// is what was actually performed before the increase was written into the
/// actual values. Resolving it here keeps the choice out of the per-set cell.
struct WorkoutDetailExerciseDisplay: Identifiable, Equatable {

    /// One recorded set. `id` is the `WorkoutSet`'s id, which is what the PR
    /// detail points at.
    struct SetValues: Identifiable, Equatable {
        let id: UUID
        /// Canonical kilograms; the cell converts for display. `0` means the set
        /// was performed at bodyweight.
        let weight: Double
        let reps: Int
        let isCompleted: Bool
    }

    let id: UUID
    let name: String
    let loadBehavior: ExerciseLoadBehavior
    /// In set order.
    let sets: [SetValues]

    init(id: UUID, name: String, loadBehavior: ExerciseLoadBehavior = .resistance, sets: [SetValues]) {
        self.id = id
        self.name = name
        self.loadBehavior = loadBehavior
        self.sets = sets
    }

    init(_ exercise: WorkoutExercise) {
        id = exercise.id
        name = exercise.exerciseName
        loadBehavior = exercise.loadBehavior
        let usePlanned = exercise.progressiveOverloadApplied
        sets = exercise.setsList
            .sorted { $0.order < $1.order }
            .map { set in
                SetValues(
                    id: set.id,
                    weight: usePlanned ? set.plannedWeight : set.actualWeight,
                    reps: usePlanned ? set.plannedReps : set.actualReps,
                    isCompleted: set.isCompleted
                )
            }
    }
}
