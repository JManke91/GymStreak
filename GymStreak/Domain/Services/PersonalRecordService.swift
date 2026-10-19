//
//  PersonalRecordService.swift
//  GymStreak
//

import Foundation
import SwiftData

/// Detects personal records (PRs) from existing WorkoutSession history, without adding new fields.
/// A PR is defined as a completed set whose estimated 1RM (Epley) exceeds every prior completed
/// set of the same exercise recorded in any prior workout session.
struct PersonalRecordService {

    /// The concrete record an exercise achieved in a session: the set that produced the new
    /// best estimated 1RM, plus the previous best for context.
    struct PRDetail: Sendable {
        /// `WorkoutExercise.stableKey` of the exercise that scored the PR.
        let exerciseKey: String
        /// The concrete workout occurrence containing the record-setting set.
        let workoutExerciseId: UUID
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
    /// Also returns per-session PR details keyed by the winning `WorkoutExercise.id` —
    /// used by workout detail to attach the record to exactly one occurrence.
    struct PRResult {
        /// session.id -> count of PR-scoring exercises in that session
        let prCountBySession: [UUID: Int]
        /// session.id -> (workout exercise id -> record details)
        let prDetailsBySession: [UUID: [UUID: PRDetail]]
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
        var prDetailsBySession: [UUID: [UUID: PRDetail]] = [:]

        for session in sorted {
            let details = records(in: session, priorBests: bestByExercise)
            // Only a record can raise a best, so the winners are the whole update.
            for detail in details.values {
                bestByExercise[detail.exerciseKey] = detail.estimatedOneRepMax
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

    /// Best estimated 1RM per `WorkoutExercise.stableKey` across `sessions` — the bar a
    /// session the history does not contain yet has to clear. Expects completed sessions; it
    /// does not filter by `endTime` itself.
    static func personalBests(sessions: [WorkoutSession]) -> [String: Double] {
        var bests: [String: Double] = [:]
        for session in sessions {
            for (key, best) in sessionBests(of: session) where best.estimatedOneRepMax > (bests[key] ?? 0) {
                bests[key] = best.estimatedOneRepMax
            }
        }
        return bests
    }

    /// The records `session` sets against `priorBests`, keyed by the winning
    /// `WorkoutExercise.id`.
    static func records(in session: WorkoutSession, priorBests: [String: Double]) -> [UUID: PRDetail] {
        records(from: sessionBests(of: session), priorBests: priorBests)
    }

    /// The records a session's bests (`sessionBests(of:)`) set against `priorBests`. Takes
    /// values, so a caller can read the session before an `await` and decide after it — the
    /// completion screen's share card checks a workout that is not saved yet.
    static func records(from sessionBests: [String: PRDetail], priorBests: [String: Double]) -> [UUID: PRDetail] {
        var details: [UUID: PRDetail] = [:]
        for (key, best) in sessionBests {
            let prior = priorBests[key]
            guard best.estimatedOneRepMax > (prior ?? 0) else { continue }
            details[best.workoutExerciseId] = PRDetail(
                exerciseKey: key,
                workoutExerciseId: best.workoutExerciseId,
                setId: best.setId,
                weight: best.weight,
                reps: best.reps,
                estimatedOneRepMax: best.estimatedOneRepMax,
                previousBest: prior
            )
        }
        return details
    }

    /// The best completed set (by estimated 1RM) of each exercise in one session, keyed by
    /// `stableKey`. `previousBest` is always nil here — this knows nothing of history.
    static func sessionBests(of session: WorkoutSession) -> [String: PRDetail] {
        var bests: [String: PRDetail] = [:]
        for exercise in session.workoutExercisesList.sorted(by: { $0.order < $1.order }) {
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
                if estimated > (bests[nameKey]?.estimatedOneRepMax ?? 0) {
                    bests[nameKey] = PRDetail(
                        exerciseKey: nameKey,
                        workoutExerciseId: exercise.id,
                        setId: set.id,
                        weight: weight,
                        reps: reps,
                        estimatedOneRepMax: estimated,
                        previousBest: nil
                    )
                }
            }
        }
        return bests
    }
}
