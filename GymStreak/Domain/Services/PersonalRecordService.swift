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

    /// Pre-computed PR lookup: for each session, the count of exercises in that session that
    /// achieved at least one PR-setting set when compared to all earlier sessions.
    ///
    /// Also returns the set of exercise names per session that achieved a PR — used by the
    /// workout detail view to draw the "PR" badge next to the exercise.
    struct PRResult {
        /// session.id -> count of PR-scoring exercises in that session
        let prCountBySession: [UUID: Int]
        /// session.id -> names of exercises that scored a PR in that session
        let prExerciseNamesBySession: [UUID: Set<String>]
    }

    /// Walks every completed session chronologically and records a PR whenever a new exercise
    /// estimated-1RM max is reached. Sessions are expected sorted; we sort defensively.
    static func computePRs(sessions: [WorkoutSession]) -> PRResult {
        let sorted = sessions
            .filter { $0.endTime != nil }
            .sorted { $0.startTime < $1.startTime }

        // exerciseName (lowercased) -> best estimated 1RM seen so far (strictly before the current session)
        var bestByExercise: [String: Double] = [:]
        var prCountBySession: [UUID: Int] = [:]
        var prExerciseNamesBySession: [UUID: Set<String>] = [:]

        for session in sorted {
            var sessionBests: [String: Double] = [:]

            // 1. Determine the max estimated-1RM for each exercise within this session.
            for exercise in session.workoutExercisesList {
                let nameKey = exercise.stableKey
                let usePlanned = exercise.progressiveOverloadApplied
                let completed = exercise.setsList.filter(\.isCompleted)
                guard !completed.isEmpty else { continue }

                let best = completed.reduce(0.0) { currentMax, set in
                    let weight = usePlanned ? set.plannedWeight : set.actualWeight
                    let reps   = usePlanned ? set.plannedReps   : set.actualReps
                    guard weight > 0, reps > 0 else { return currentMax }
                    let estimated = weight * (1 + Double(reps) / 30.0)
                    return max(currentMax, estimated)
                }
                guard best > 0 else { continue }
                sessionBests[nameKey] = max(sessionBests[nameKey] ?? 0, best)
            }

            // 2. Compare against historical bests (strictly before this session).
            var prNames: Set<String> = []
            for (nameKey, sessionBest) in sessionBests {
                let prior = bestByExercise[nameKey] ?? 0
                if sessionBest > prior {
                    prNames.insert(nameKey)
                    bestByExercise[nameKey] = sessionBest
                }
            }

            if !prNames.isEmpty {
                prCountBySession[session.id] = prNames.count
                prExerciseNamesBySession[session.id] = prNames
            }
        }

        return PRResult(
            prCountBySession: prCountBySession,
            prExerciseNamesBySession: prExerciseNamesBySession
        )
    }
}
