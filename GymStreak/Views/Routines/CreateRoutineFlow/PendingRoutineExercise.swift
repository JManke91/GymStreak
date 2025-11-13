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

    init(exercise: Exercise, sets: [ExerciseSet], order: Int) {
        self.exercise = exercise
        self.sets = sets
        self.order = order
    }

    /// Summary of sets for display (e.g., "3 sets • 8-12 reps • 45kg")
    var setSummary: String {
        guard !sets.isEmpty else { return "No sets configured" }

        let setCount = sets.count
        let repsRange = getRepsRange()
        let weightRange = getWeightRange()

        var summary = "\(setCount) set\(setCount == 1 ? "" : "s")"

        if !repsRange.isEmpty {
            summary += " • \(repsRange)"
        }

        if !weightRange.isEmpty {
            summary += " • \(weightRange)"
        }

        return summary
    }

    private func getRepsRange() -> String {
        let reps = sets.map { $0.reps }
        guard let minReps = reps.min(), let maxReps = reps.max() else { return "" }

        if minReps == maxReps {
            return "\(minReps) reps"
        } else {
            return "\(minReps)-\(maxReps) reps"
        }
    }

    private func getWeightRange() -> String {
        let weights = sets.map { $0.weight }
        guard let minWeight = weights.min(), let maxWeight = weights.max() else { return "" }

        // Don't show weight if all are 0 (bodyweight exercise)
        if maxWeight == 0 {
            return ""
        }

        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0

        if minWeight == maxWeight {
            return "\(formatter.string(from: NSNumber(value: minWeight)) ?? "0")kg"
        } else {
            return "\(formatter.string(from: NSNumber(value: minWeight)) ?? "0")-\(formatter.string(from: NSNumber(value: maxWeight)) ?? "0")kg"
        }
    }
}
