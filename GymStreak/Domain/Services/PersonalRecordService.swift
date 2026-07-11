//
//  PersonalRecordService.swift
//  GymStreak
//

import Foundation
import SwiftData

/// Detects personal records (PRs) from existing WorkoutSession history, without adding new fields.
/// A PR is defined as a completed set whose estimated 1RM (Epley) exceeds every prior completed
/// set of the same exercise recorded in any prior workout session.
@MainActor
struct PersonalRecordService {

    /// The concrete record an exercise achieved in a session: the set that produced the new
    /// best estimated 1RM, plus the previous best for context.
    struct PRDetail {
        /// `WorkoutExercise.stableKey` of the exercise that scored the PR.
        let exerciseKey: String
        /// The completed set that achieved the new best estimated 1RM.
        let setId: UUID
        let weight: Double
        let reps: Int
        let estimatedOneRepMax: Double
        /// Best estimated 1RM before this session; nil when the exercise was performed for the first time.
        let previousBest: Double?
    }

    /// Pre-computed PR lookup: for each session, the count of exercises in that session that
    /// achieved at least one PR-setting set when compared to all earlier sessions.
    ///
    /// Also returns per-session PR details (keyed by exercise `stableKey`) — used by the
    /// workout detail view to show which record was achieved and by which set.
    struct PRResult {
        /// session.id -> count of PR-scoring exercises in that session
        let prCountBySession: [UUID: Int]
        /// session.id -> (exercise stableKey -> record details) for exercises that scored a PR
        let prDetailsBySession: [UUID: [String: PRDetail]]
    }

    /// Walks every completed session chronologically and records a PR whenever a new exercise
    /// estimated-1RM max is reached. Sessions are expected sorted; we sort defensively.
    static func computePRs(sessions: [WorkoutSession]) -> PRResult {
        let sorted = sessions
            .filter { $0.endTime != nil }
            .sorted { $0.startTime < $1.startTime }

        // exercise stableKey -> best estimated 1RM seen so far (strictly before the current session)
        var bestByExercise: [String: Double] = [:]
        var prCountBySession: [UUID: Int] = [:]
        var prDetailsBySession: [UUID: [String: PRDetail]] = [:]

        for session in sorted {
            // 1. Determine the best set (by estimated 1RM) for each exercise within this session.
            var sessionBests: [String: (setId: UUID, weight: Double, reps: Int, estimated: Double)] = [:]
            for exercise in session.workoutExercisesList {
                let nameKey = exercise.stableKey
                let usePlanned = exercise.progressiveOverloadApplied
                for set in exercise.setsList where set.isCompleted {
                    let enteredWeight = usePlanned ? set.plannedWeight : set.actualWeight
                    let reps   = usePlanned ? set.plannedReps   : set.actualReps
                    guard reps > 0,
                          enteredWeight > 0 || exercise.loadBehavior.isCounterweightAssistance,
                          let weight = ExerciseLoadMetrics.effectiveWeight(
                            enteredWeight: enteredWeight,
                            behavior: exercise.loadBehavior,
                            bodyWeightKg: session.bodyWeightKg
                          ) else { continue }
                    let estimated = ExerciseLoadMetrics.estimatedOneRepMax(weight: weight, reps: reps)
                    if estimated > (sessionBests[nameKey]?.estimated ?? 0) {
                        sessionBests[nameKey] = (set.id, weight, reps, estimated)
                    }
                }
            }

            // 2. Compare against historical bests (strictly before this session).
            var details: [String: PRDetail] = [:]
            for (nameKey, best) in sessionBests {
                let prior = bestByExercise[nameKey]
                guard best.estimated > (prior ?? 0) else { continue }
                details[nameKey] = PRDetail(
                    exerciseKey: nameKey,
                    setId: best.setId,
                    weight: best.weight,
                    reps: best.reps,
                    estimatedOneRepMax: best.estimated,
                    previousBest: prior
                )
                bestByExercise[nameKey] = best.estimated
            }

            if !details.isEmpty {
                prCountBySession[session.id] = details.count
                prDetailsBySession[session.id] = details
            }
        }

        return PRResult(
            prCountBySession: prCountBySession,
            prDetailsBySession: prDetailsBySession
        )
    }
}
