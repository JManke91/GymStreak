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

    /// Builds one row per *live* exercise in the user's Exercise library.
    ///
    /// Rules:
    /// - Workout exercises whose `exerciseId` matches a live exercise are folded into that row.
    /// - Workout exercises with no `exerciseId` (legacy data) are matched by lowercased name.
    /// - Workout exercises that don't resolve to any live exercise are dropped — this is what
    ///   keeps deleted exercises from leaking into the Progress tab.
    ///
    /// Trend is the % change between the first and last session's max estimated 1RM.
    static func build(
        sessions: [WorkoutSession],
        liveExercises: [Exercise]
    ) -> [FortschrittExerciseModel] {
        var liveById: [UUID: Exercise] = [:]
        var liveByName: [String: [Exercise]] = [:]
        for exercise in liveExercises {
            liveById[exercise.id] = exercise
            liveByName[exercise.name.lowercased(), default: []].append(exercise)
        }

        let finished = sessions
            .filter { $0.endTime != nil }
            .sorted { $0.startTime < $1.startTime }

        struct Accumulator {
            var displayName: String
            var muscleGroups: [String]
            var liveId: UUID
            var sessionValues: [(date: Date, est1RM: Double, maxWeight: Double)] = []
        }

        var map: [UUID: Accumulator] = [:]

        for session in finished {
            for workoutExercise in session.workoutExercisesList {
                let completed = workoutExercise.setsList.filter(\.isCompleted)
                guard !completed.isEmpty else { continue }
                guard let live = resolveLive(
                    workoutExercise: workoutExercise,
                    byId: liveById,
                    byName: liveByName
                ) else { continue }

                var acc = map[live.id] ?? Accumulator(
                    displayName: live.name,
                    muscleGroups: live.muscleGroups,
                    liveId: live.id
                )
                acc.displayName = live.name
                acc.muscleGroups = live.muscleGroups

                let usePlanned = workoutExercise.progressiveOverloadApplied
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
                map[live.id] = acc
            }
        }

        let models: [FortschrittExerciseModel] = map.map { id, acc in
            let values = acc.sessionValues.sorted { $0.date < $1.date }
            let sparkline = values.map(\.est1RM)
            let trend: Double? = {
                guard let first = values.first, let last = values.last,
                      first.est1RM > 0, values.count >= 2 else { return nil }
                return ((last.est1RM - first.est1RM) / first.est1RM) * 100
            }()
            return FortschrittExerciseModel(
                id: id.uuidString,
                name: acc.displayName,
                primaryMuscleGroup: acc.muscleGroups.first ?? "General",
                muscleGroups: acc.muscleGroups,
                exerciseId: id,
                workoutCount: values.count,
                lastPerformed: values.last?.date,
                trendPct: trend,
                sparkline: sparkline.isEmpty ? [0] : sparkline
            )
        }

        return models.sorted { $0.workoutCount > $1.workoutCount }
    }

    /// Resolves a workout exercise to its live library entry. Prefers the stored
    /// `exerciseId` link; falls back to a case-insensitive name match for legacy
    /// rows that pre-date the `exerciseId` field. The fallback is **only** used
    /// when the name is unique in the live library — otherwise the legacy row is
    /// ambiguous (e.g. "Biceps Curls" exists as both dumbbell and barbell entries)
    /// and we drop it rather than misattribute its sets to one variant.
    private static func resolveLive(
        workoutExercise: WorkoutExercise,
        byId: [UUID: Exercise],
        byName: [String: [Exercise]]
    ) -> Exercise? {
        if let id = workoutExercise.exerciseId, let live = byId[id] {
            return live
        }
        let candidates = byName[workoutExercise.exerciseName.lowercased()] ?? []
        return candidates.count == 1 ? candidates[0] : nil
    }
}
