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

/// The exercise section as the screen draws it: a standalone exercise is a
/// one-member group, a superset is one group carrying the letter the rest of
/// the app knows it by.
///
/// Built once per load, next to the other display state — the walk below
/// touches every exercise's `setsList`, which must never happen from `body`.
struct WorkoutDetailExerciseGroup: Identifiable, Equatable {
    /// The superset's id, or the lone member's exercise id.
    let id: UUID
    /// `nil` for a standalone exercise — and for a superset with a single
    /// member, which is drawn as one; a frame around one block says nothing.
    /// Letters follow first appearance in `order`, exactly as the active
    /// workout labels them, so "Superset B" here is the same B the user
    /// trained under.
    let supersetLetter: String?
    /// In `supersetOrder` for a superset.
    let exercises: [WorkoutDetailExerciseDisplay]

    static func make(from session: WorkoutSession) -> [WorkoutDetailExerciseGroup] {
        let letters = SupersetLabelProvider.labels(for: session.workoutExercisesList)
        return session.exercisesGroupedBySupersets.compactMap { members in
            guard let first = members.first else { return nil }
            let supersetId = first.supersetId
            let letter = members.count > 1 ? supersetId.flatMap { letters[$0] } : nil
            return WorkoutDetailExerciseGroup(
                id: supersetId ?? first.id,
                supersetLetter: letter,
                exercises: members.map(WorkoutDetailExerciseDisplay.init)
            )
        }
    }
}
