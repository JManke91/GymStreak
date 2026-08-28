//
//  PendingRoutineExercise.swift
//  GymStreak
//
//  Created by Claude Code
//

import Foundation

/// Temporary model to hold exercise data during routine creation before persisting to SwiftData
struct PendingRoutineExercise: Identifiable {
    let id = UUID()
    let exercise: Exercise
    var sets: [ExerciseSet]
    var order: Int
    /// Alternative exercises picked during configuration (each with its own set
    /// scheme); materialized into RoutineExerciseAlternative models at routine save.
    var alternatives: [PendingAlternative]
    /// Rep-range goal picked during configuration; copied onto the RoutineExercise
    /// at routine save. Nil/nil means no goal.
    var targetRepMin: Int?
    var targetRepMax: Int?

    init(
        exercise: Exercise,
        sets: [ExerciseSet],
        order: Int,
        alternatives: [PendingAlternative] = [],
        targetRepMin: Int? = nil,
        targetRepMax: Int? = nil
    ) {
        self.exercise = exercise
        self.sets = sets
        self.order = order
        self.alternatives = alternatives
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
    }

    /// Summary of sets for display, e.g. "3 sets • 8-12 reps • 45 kg".
    ///
    /// - Parameter unit: the unit the calling screen renders in, read from
    ///   `\.weightUnit`.
    func setSummary(in unit: WeightUnit) -> String {
        guard !sets.isEmpty else { return "configure_exercise.empty.title".localized }

        let parts = [
            "routine.sets_count".localized(sets.count),
            repsRange,
            weightRange(in: unit)
        ]
        return parts.filter { !$0.isEmpty }.joined(separator: " • ")
    }

    private var repsRange: String {
        let reps = sets.map { $0.reps }
        guard let minReps = reps.min(), let maxReps = reps.max() else { return "" }

        return minReps == maxReps
            ? "set.reps".localized(minReps)
            : "set.reps_range".localized(minReps, maxReps)
    }

    /// Empty for a bodyweight scheme (every set at 0), which is how the summary
    /// stays "3 sets • 10 reps" instead of claiming a weight.
    private func weightRange(in unit: WeightUnit) -> String {
        let weights = sets.map { $0.weight }
        guard let minWeight = weights.min(), let maxWeight = weights.max(), maxWeight > 0 else {
            return ""
        }

        if minWeight == maxWeight {
            return WeightFormatting.label(maxWeight, in: unit)
        }
        // One unit word for the pair — "40–45 kg", not "40 kg–45 kg".
        return WeightFormatting.labelled(
            "set.weight_range".localized(
                WeightFormatting.number(minWeight, in: unit),
                WeightFormatting.number(maxWeight, in: unit)
            ),
            in: unit
        )
    }
}
