//
//  RoutineMetricsService.swift
//  GymStreak
//
//  Pure display metrics for routines: set totals, estimated duration and
//  the ordered set of muscle groups a routine trains. Introduced with the
//  Routinen & Übungen redesign (docs/routines-exercises-redesign.md).
//

import Foundation

enum RoutineMetricsService {
    /// Total number of planned sets across all exercises.
    static func totalSets(for routine: Routine) -> Int {
        routine.routineExercisesList.reduce(0) { $0 + $1.setsList.count }
    }

    /// Rough duration estimate in minutes: ~40s of work per set, the exercise's
    /// configured rest between sets, plus ~60s transition per exercise.
    static func estimatedDurationMinutes(for routine: Routine) -> Int {
        var seconds = 0.0
        for exercise in routine.routineExercisesList {
            let setCount = exercise.setsList.count
            guard setCount > 0 else { continue }
            let rest = exercise.setsList.first?.restTime ?? 60
            seconds += Double(setCount) * 40
            seconds += Double(max(0, setCount - 1)) * rest
            seconds += 60
        }
        return max(1, Int((seconds / 60).rounded()))
    }

    /// Unique primary muscle groups of the routine's exercises, in exercise order.
    static func primaryMuscleGroups(for routine: Routine) -> [String] {
        var seen: [String] = []
        for exercise in routine.routineExercisesList.sorted(by: { $0.order < $1.order }) {
            guard let muscle = exercise.exercise?.primaryMuscleGroup else { continue }
            if !seen.contains(muscle) {
                seen.append(muscle)
            }
        }
        return seen
    }

    /// Compact set summary, e.g. "3 × 6 Wdh · 90 kg" when all sets are uniform,
    /// otherwise "4 Sätze". Formatting strings are provided by the caller so the
    /// Domain layer stays localization-free.
    static func uniformSetScheme(reps: [Int], weights: [Double]) -> (reps: Int, weight: Double)? {
        guard let firstReps = reps.first, let firstWeight = weights.first else { return nil }
        guard reps.allSatisfy({ $0 == firstReps }), weights.allSatisfy({ $0 == firstWeight }) else { return nil }
        return (firstReps, firstWeight)
    }

    /// Compact scheme summary for picker rows, e.g. "3×10", "4×8–12 · 20kg".
    /// Weight is appended only when uniform across all sets and non-zero
    /// (alternatives commonly seed at weight 0). Shared by the in-workout Swap
    /// picker and the routine alternatives browse sheet so both read identically.
    static func setSchemeSummary(reps: [Int], weights: [Double]) -> String? {
        guard !reps.isEmpty else { return nil }
        let repsPart = reps.min() == reps.max()
            ? "\(reps[0])"
            : "\(reps.min() ?? 0)–\(reps.max() ?? 0)"
        var summary = "\(reps.count)×\(repsPart)"
        if let weight = weights.first, weight > 0, weights.allSatisfy({ $0 == weight }) {
            summary += " · \(String(format: "%gkg", weight))"
        }
        return summary
    }
}
