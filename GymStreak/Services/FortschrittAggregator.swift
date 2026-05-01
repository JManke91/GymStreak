//
//  FortschrittAggregator.swift
//  GymStreak
//

import Foundation
import SwiftData

/// Pure aggregator that turns completed WorkoutSessions into the row models used by the
/// Fortschritt tab. Pulled into its own type so the heavy per-exercise computation can be
/// called from a background task and the tests can drive it directly.
@MainActor
struct FortschrittAggregator {

    /// Builds one row per distinct exercise name. Trend is computed as the % change between
    /// the first and last session's max estimated 1RM over the entire history.
    static func build(sessions: [WorkoutSession]) -> [FortschrittExerciseModel] {
        let finished = sessions
            .filter { $0.endTime != nil }
            .sorted { $0.startTime < $1.startTime }

        struct Accumulator {
            var displayName: String = ""
            var muscleGroups: [String] = []
            var exerciseId: UUID? = nil
            var sessionValues: [(date: Date, est1RM: Double, maxWeight: Double)] = []
        }

        var map: [String: Accumulator] = [:]

        for session in finished {
            for exercise in session.workoutExercisesList {
                let completed = exercise.setsList.filter(\.isCompleted)
                guard !completed.isEmpty else { continue }
                let key = exercise.stableKey
                var acc = map[key] ?? Accumulator(displayName: exercise.exerciseName, muscleGroups: exercise.muscleGroups, exerciseId: exercise.exerciseId, sessionValues: [])
                if acc.muscleGroups.isEmpty { acc.muscleGroups = exercise.muscleGroups }

                let usePlanned = exercise.progressiveOverloadApplied
                var bestEst1RM: Double = 0
                var bestWeight: Double = 0
                for set in completed {
                    let w = usePlanned ? set.plannedWeight : set.actualWeight
                    let r = usePlanned ? set.plannedReps   : set.actualReps
                    guard w > 0, r > 0 else { continue }
                    let est = w * (1 + Double(r) / 30.0)
                    bestEst1RM = max(bestEst1RM, est)
                    bestWeight = max(bestWeight, w)
                }
                acc.sessionValues.append((session.startTime, bestEst1RM, bestWeight))
                map[key] = acc
            }
        }

        let models: [FortschrittExerciseModel] = map.map { key, acc in
            let values = acc.sessionValues.sorted { $0.date < $1.date }
            let sparkline = values.map(\.est1RM)
            let trend: Double? = {
                guard let first = values.first, let last = values.last,
                      first.est1RM > 0, values.count >= 2 else { return nil }
                return ((last.est1RM - first.est1RM) / first.est1RM) * 100
            }()
            return FortschrittExerciseModel(
                id: key,
                name: acc.displayName,
                primaryMuscleGroup: acc.muscleGroups.first ?? "General",
                muscleGroups: acc.muscleGroups,
                exerciseId: acc.exerciseId,
                workoutCount: values.count,
                lastPerformed: values.last?.date,
                trendPct: trend,
                sparkline: sparkline.isEmpty ? [0] : sparkline
            )
        }

        return models.sorted { $0.workoutCount > $1.workoutCount }
    }
}
