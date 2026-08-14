//
//  ExerciseProgressAggregator.swift
//  GymStreak
//

import Foundation
import SwiftData

/// Pure aggregator that turns completed `WorkoutSession`s into the exercise detail
/// screen's chart series and its "recent sessions" list.
///
/// Extracted from `ExerciseProgressService` (audit P1.2) so the whole-history
/// traversal can run inside `SwiftDataHistorySnapshotStore`'s model actor instead of
/// synchronously on the main actor. Nothing here may become `@MainActor`: the actor
/// calls it from its own executor (`docs/swift6-concurrency.md` §10 rule 3), and the
/// same rule is why it lives in `Domain/Services/` rather than next to the store.
///
/// Every entry point takes already-fetched models and returns immutable values, so it
/// is directly testable without a `ModelContext` fetch.
struct ExerciseProgressAggregator {

    // MARK: - Combined entry point

    /// Builds both halves of the exercise detail screen from one session array.
    ///
    /// - Parameters:
    ///   - sessions: completed sessions, in any order — each builder sorts what it needs.
    ///   - liveExercises: the user's `Exercise` library, used to resolve load behaviour
    ///     and to decide whether a legacy name match is unambiguous.
    ///   - startDate: chart window lower bound. Only the chart series is windowed;
    ///     the recent-session list is deliberately all-time, matching the previous behaviour.
    static func buildSnapshot(
        sessions: [WorkoutSession],
        liveExercises: [Exercise],
        exerciseName: String,
        exerciseId: UUID?,
        startDate: Date,
        recentSessionLimit: Int
    ) -> ExerciseProgressSnapshot {
        let nameIsUnique = isNameUnique(exerciseName, in: liveExercises)
        let behavior = loadBehavior(
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            in: liveExercises
        )

        return ExerciseProgressSnapshot(
            data: buildProgress(
                sessions: sessions,
                exerciseName: exerciseName,
                exerciseId: exerciseId,
                nameIsUnique: nameIsUnique,
                loadBehavior: behavior,
                startDate: startDate
            ),
            recentSessions: buildRecentSessions(
                sessions: sessions,
                exerciseName: exerciseName,
                exerciseId: exerciseId,
                nameIsUnique: nameIsUnique,
                limit: recentSessionLimit
            )
        )
    }

    // MARK: - Chart series

    /// One data point per session that contains at least one completed set of the exercise.
    static func buildProgress(
        sessions: [WorkoutSession],
        exerciseName: String,
        exerciseId: UUID?,
        nameIsUnique: Bool,
        loadBehavior: ExerciseLoadBehavior,
        startDate: Date
    ) -> ExerciseProgressData {
        let windowed = sessions
            .filter { $0.endTime != nil && $0.startTime >= startDate }
            .sorted { $0.startTime < $1.startTime }

        let matchedBySession = windowed.map { session in
            (session, session.workoutExercisesList.filter {
                matches($0, exerciseId: exerciseId, exerciseName: exerciseName, nameIsUnique: nameIsUnique)
                    && $0.loadBehavior == loadBehavior
            })
        }
        let relevant = matchedBySession.filter { !$0.1.isEmpty }
        let usesEffectiveLoad = loadBehavior.isCounterweightAssistance
            && !relevant.isEmpty
            && relevant.allSatisfy { $0.0.bodyWeightKg != nil }
        var dataPoints: [ExerciseProgressDataPoint] = []

        for (session, matchingExercises) in matchedBySession {

            // Aggregate all matching exercises into a single data point per session
            var sessionMaxWeight: Double = 0
            var sessionTotalVolume: Double = 0
            var sessionTotalReps: Int = 0
            var sessionTotalSets: Int = 0
            var sessionBest1RM: Double = 0
            var hasCompletedSets = false
            var hasAssistanceValue = false

            for exercise in matchingExercises {
                let completedSets = exercise.setsList.filter(\.isCompleted)
                guard !completedSets.isEmpty else { continue }
                hasCompletedSets = true

                let usePlanned = exercise.progressiveOverloadApplied
                let enteredWeights = completedSets.map { usePlanned ? $0.plannedWeight : $0.actualWeight }
                if loadBehavior.isCounterweightAssistance && !usesEffectiveLoad {
                    let leastAssistance = enteredWeights.min() ?? 0
                    sessionMaxWeight = hasAssistanceValue
                        ? min(sessionMaxWeight, leastAssistance)
                        : leastAssistance
                    hasAssistanceValue = true
                } else {
                    let effectiveWeights = enteredWeights.compactMap {
                        ExerciseLoadMetrics.effectiveWeight(
                            enteredWeight: $0,
                            behavior: loadBehavior,
                            bodyWeightKg: session.bodyWeightKg
                        )
                    }
                    sessionMaxWeight = max(sessionMaxWeight, effectiveWeights.max() ?? 0)
                }

                if usesEffectiveLoad || !loadBehavior.isCounterweightAssistance {
                    sessionTotalVolume += completedSets.reduce(0) {
                        let entered = usePlanned ? $1.plannedWeight : $1.actualWeight
                        let reps = usePlanned ? $1.plannedReps : $1.actualReps
                        let weight = ExerciseLoadMetrics.effectiveWeight(
                            enteredWeight: entered,
                            behavior: loadBehavior,
                            bodyWeightKg: session.bodyWeightKg
                        ) ?? 0
                        return $0 + (weight * Double(reps))
                    }
                }
                sessionTotalReps += completedSets.reduce(0) { $0 + (usePlanned ? $1.plannedReps : $1.actualReps) }
                sessionTotalSets += completedSets.count

                let estimated1RM = usesEffectiveLoad || !loadBehavior.isCounterweightAssistance
                    ? bestEstimated1RM(
                        from: completedSets,
                        usePlannedValues: usePlanned,
                        behavior: loadBehavior,
                        bodyWeightKg: session.bodyWeightKg
                    )
                    : 0
                sessionBest1RM = max(sessionBest1RM, estimated1RM)
            }

            guard hasCompletedSets else { continue }

            dataPoints.append(
                ExerciseProgressDataPoint(
                    date: session.startTime,
                    maxWeight: sessionMaxWeight,
                    estimated1RM: sessionBest1RM,
                    totalVolume: sessionTotalVolume,
                    totalSets: sessionTotalSets,
                    totalReps: sessionTotalReps,
                    workoutSessionId: session.id
                )
            )
        }

        return ExerciseProgressData(
            exerciseName: exerciseName,
            dataPoints: dataPoints,
            loadBehavior: loadBehavior,
            usesEffectiveLoad: usesEffectiveLoad
        )
    }

    // MARK: - Recent sessions

    /// The `limit` most recent sessions containing completed sets of the exercise.
    ///
    /// Unlike the chart series this ignores the selected timeframe and does not filter
    /// by load behaviour — it reproduces the list the exercise detail screen already
    /// showed, which read the first matching `WorkoutExercise` per session.
    static func buildRecentSessions(
        sessions: [WorkoutSession],
        exerciseName: String,
        exerciseId: UUID?,
        nameIsUnique: Bool,
        limit: Int
    ) -> [ExerciseRecentSession] {
        let ordered = sessions
            .filter { $0.endTime != nil }
            .sorted { $0.startTime > $1.startTime }

        var collected: [ExerciseRecentSession] = []
        for session in ordered {
            guard let exercise = session.workoutExercisesList.first(where: {
                matches($0, exerciseId: exerciseId, exerciseName: exerciseName, nameIsUnique: nameIsUnique)
            }) else { continue }

            let usePlanned = exercise.progressiveOverloadApplied
            let entries = exercise.setsList
                .sorted { $0.order < $1.order }
                .filter(\.isCompleted)
                .map { set in
                    ExerciseRecentSession.SetEntry(
                        id: set.id,
                        weight: usePlanned ? set.plannedWeight : set.actualWeight,
                        reps: usePlanned ? set.plannedReps : set.actualReps
                    )
                }
            guard !entries.isEmpty else { continue }

            collected.append(
                ExerciseRecentSession(id: session.id, date: session.startTime, sets: entries)
            )
            if collected.count >= limit { break }
        }
        return collected
    }

    // MARK: - Identity resolution

    /// Decides whether a `WorkoutExercise` belongs to the exercise the caller is asking about.
    ///
    /// When an `exerciseId` is provided, an exact id match always wins. The case-insensitive
    /// name fallback (for legacy rows where `WorkoutExercise.exerciseId` is `nil`) is **only**
    /// used when `nameIsUnique` is true — i.e. there is exactly one live `Exercise` with that
    /// name. When two live exercises share a name (e.g. "Biceps Curls" with dumbbell and
    /// barbell variants), legacy untagged rows are ambiguous, so we drop them from both
    /// charts rather than double-count them under each variant.
    static func matches(
        _ exercise: WorkoutExercise,
        exerciseId: UUID?,
        exerciseName: String,
        nameIsUnique: Bool
    ) -> Bool {
        matches(
            candidateExerciseId: exercise.exerciseId,
            candidateExerciseName: exercise.exerciseName,
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            nameIsUnique: nameIsUnique
        )
    }

    /// The rule above, over values rather than a `WorkoutExercise`.
    ///
    /// `PreviousPerformanceResolver` also has to apply it to the *current* workout's
    /// exercises, which reach it as `PreviousPerformanceLookup.Query` values because no
    /// `@Model` may cross into the model actor (audit P1.6). One implementation, so the
    /// two sides of a comparison can never disagree about what counts as the same
    /// exercise.
    static func matches(
        candidateExerciseId: UUID?,
        candidateExerciseName: String,
        exerciseId: UUID?,
        exerciseName: String,
        nameIsUnique: Bool
    ) -> Bool {
        if let exerciseId {
            if candidateExerciseId == exerciseId { return true }
            if nameIsUnique,
               candidateExerciseId == nil,
               candidateExerciseName.lowercased() == exerciseName.lowercased() {
                return true
            }
            return false
        }
        if nameIsUnique {
            return candidateExerciseName.lowercased() == exerciseName.lowercased()
        }
        return false
    }

    /// Whether `name` is unique (case-insensitive) among the user's live `Exercise` library.
    /// Drives the legacy-row name fallback in `matches(_:exerciseId:exerciseName:nameIsUnique:)`.
    static func isNameUnique(_ name: String, in liveExercises: [Exercise]) -> Bool {
        let target = name.lowercased()
        return liveExercises.filter { $0.name.lowercased() == target }.count <= 1
    }

    /// The live library's load behaviour for the charted exercise, resolved by id when
    /// available and by name otherwise. Falls back to `.resistance` for exercises that
    /// no longer exist in the library.
    static func loadBehavior(
        exerciseId: UUID?,
        exerciseName: String,
        in liveExercises: [Exercise]
    ) -> ExerciseLoadBehavior {
        if let exerciseId, let exercise = liveExercises.first(where: { $0.id == exerciseId }) {
            return exercise.loadBehavior
        }
        return liveExercises
            .first { $0.name.caseInsensitiveCompare(exerciseName) == .orderedSame }?
            .loadBehavior ?? .resistance
    }

    // MARK: - Private helpers

    /// Highest Epley-estimated 1RM across the given sets.
    private static func bestEstimated1RM(
        from sets: [WorkoutSet],
        usePlannedValues: Bool,
        behavior: ExerciseLoadBehavior,
        bodyWeightKg: Double?
    ) -> Double {
        var best1RM: Double = 0

        for set in sets {
            let enteredWeight = usePlannedValues ? set.plannedWeight : set.actualWeight
            let reps = usePlannedValues ? set.plannedReps : set.actualReps
            guard set.isCompleted,
                  let weight = ExerciseLoadMetrics.effectiveWeight(
                    enteredWeight: enteredWeight,
                    behavior: behavior,
                    bodyWeightKg: bodyWeightKg
                  ),
                  weight > 0 else { continue }

            best1RM = max(best1RM, ExerciseLoadMetrics.estimatedOneRepMax(weight: weight, reps: reps))
        }

        return best1RM
    }
}
