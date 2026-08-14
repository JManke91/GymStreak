//
//  WorkoutAnalysisAggregator.swift
//  GymStreak
//
//  Builds a `WorkoutAnalysisInput` for the AI Coach workout detail surface.
//  Compares a completed workout against the most recent previous session
//  of the same routine.
//

import Foundation
import SwiftData

/// Builds AI Coach input for the workout detail analysis surface.
///
/// Returns `nil` when no previous same-routine session exists or the session
/// has fewer than 2 completed sets (insufficient data for meaningful analysis).
@MainActor
struct WorkoutAnalysisAggregator {

    // MARK: - Minimum thresholds

    /// Minimum completed sets in the current session before analysis is attempted.
    static let minimumSetsThreshold = 2

    /// Minimum completion percentage — below this the workout was aborted so
    /// early that a comparison against the previous session is meaningless.
    static let minimumCompletionThreshold = 40

    // MARK: - Public API

    /// Builds the AI Coach input for a workout analysis.
    /// - Parameters:
    ///   - session: The workout session to analyse.
    ///   - locale: The user's current locale.
    ///   - modelContext: The SwiftData context to query history from.
    ///   - comparisons: Per-exercise vs-previous comparisons, already resolved by
    ///     `ExerciseProgressProviding`. Passed in rather than built here (audit P1.6):
    ///     the caller is `async` and the scan behind them belongs on the model actor,
    ///     whereas this type is `@MainActor`. It also removes the ad-hoc service
    ///     construction that bypassed `AppDependencies`.
    /// - Returns: A `WorkoutAnalysisInput` or `nil` if insufficient data.
    func buildInput(
        session: WorkoutSession,
        locale: Locale,
        modelContext: ModelContext,
        comparisons: [ExerciseComparisonResult]
    ) -> WorkoutAnalysisInput? {
        // Gate: minimum completed sets
        let completedSets = session.workoutExercisesList
            .flatMap(\.setsList)
            .filter(\.isCompleted)
        guard completedSets.count >= Self.minimumSetsThreshold else { return nil }

        // Gate: heavily aborted workouts produce misleading comparisons
        guard session.completionPercentage >= Self.minimumCompletionThreshold else { return nil }

        // Find the previous session with the same routine name
        guard let previousSession = findPreviousSession(
            routineName: session.routineName,
            before: session.startTime,
            excludingId: session.id,
            modelContext: modelContext
        ) else { return nil }

        // Build per-exercise comparison data. Keyed by the exercise each comparison
        // describes rather than by position, which mispairs as soon as the two orderings
        // differ and drops the tail when the counts do.
        let comparisonsByExercise = Dictionary(
            comparisons.map { ($0.workoutExerciseId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let sortedExercises = session.workoutExercisesList.sorted(by: { $0.order < $1.order })

        let exerciseInputs = sortedExercises.map { exercise in
            buildExerciseInput(exercise: exercise, comparison: comparisonsByExercise[exercise.id])
        }

        // Gate: at least one exercise must have previous data to compare —
        // an all-first-time session has nothing to analyse.
        guard exerciseInputs.contains(where: { !$0.isFirstTime }) else { return nil }

        // Detect PRs
        let newPRs = detectNewPRs(session: session, modelContext: modelContext)

        // Days between sessions — fed to the model instead of raw dates,
        // which it tends to echo verbatim into the narrative.
        let daysSincePrevious = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: previousSession.startTime),
            to: Calendar.current.startOfDay(for: session.startTime)
        ).day ?? 0

        // Compute previous session stats
        let previousSetsCount = previousSession.workoutExercisesList
            .flatMap(\.setsList)
            .filter(\.isCompleted)
            .count

        // Exercises done last time but skipped in this session
        let currentKeys = Set(session.workoutExercisesList.map(\.stableKey))
        let droppedExerciseCount = previousSession.workoutExercisesList
            .filter { !currentKeys.contains($0.stableKey) }
            .count

        return WorkoutAnalysisInput(
            locale: locale.identifier,
            routineName: session.routineName,
            daysSincePrevious: daysSincePrevious,
            currentDurationMinutes: Int(session.duration / 60),
            currentTotalSets: completedSets.count,
            currentCompletionPercentage: session.completionPercentage,
            previousTotalSets: previousSetsCount,
            droppedExerciseCount: droppedExerciseCount,
            exercises: exerciseInputs,
            newPRs: newPRs
        )
    }

    /// Returns `true` if a previous same-routine session exists.
    /// Cheaper than `buildInput` — use for gating the button visibility.
    func hasPreviousSession(
        session: WorkoutSession,
        modelContext: ModelContext
    ) -> Bool {
        findPreviousSession(
            routineName: session.routineName,
            before: session.startTime,
            excludingId: session.id,
            modelContext: modelContext
        ) != nil
    }

    // MARK: - Private helpers

    private func findPreviousSession(
        routineName: String,
        before date: Date,
        excludingId: UUID,
        modelContext: ModelContext
    ) -> WorkoutSession? {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.startTime < date && session.endTime != nil
            },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )

        guard let sessions = try? modelContext.fetch(descriptor) else { return nil }

        return sessions.first { session in
            session.id != excludingId
            && session.routineName.lowercased() == routineName.lowercased()
        }
    }

    private func buildExerciseInput(
        exercise: WorkoutExercise,
        comparison: ExerciseComparisonResult?
    ) -> WorkoutAnalysisExerciseInput {
        let usePlanned = exercise.progressiveOverloadApplied
        let sortedSets = exercise.setsList.sorted(by: { $0.order < $1.order })
        let isFirstTime = comparison?.isFirstTime ?? true

        var setInputs: [WorkoutAnalysisSetInput] = []
        let setComparisons = comparison?.currentPerformance.sets ?? []

        for (index, set) in sortedSets.enumerated() {
            let weight = usePlanned ? set.plannedWeight : set.actualWeight
            let reps = usePlanned ? set.plannedReps : set.actualReps
            let setComp = index < setComparisons.count ? setComparisons[index] : nil

            setInputs.append(WorkoutAnalysisSetInput(
                setNumber: index + 1,
                currentWeightKg: weight,
                currentReps: reps,
                isCompleted: set.isCompleted,
                previousWeightKg: setComp?.previousWeight,
                previousReps: setComp?.previousReps
            ))
        }

        return WorkoutAnalysisExerciseInput(
            exerciseName: exercise.exerciseName,
            isFirstTime: isFirstTime,
            sets: setInputs
        )
    }

    /// Detects exercises in `session` that set a new all-time estimated-1RM PR.
    /// Uses the Epley formula: weight * (1 + reps / 30.0).
    private func detectNewPRs(
        session: WorkoutSession,
        modelContext: ModelContext
    ) -> [PRSummary] {
        let sessionStart = session.startTime
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { s in
                s.startTime <= sessionStart && s.endTime != nil
            },
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        guard let allSessions = try? modelContext.fetch(descriptor) else { return [] }

        // Build prior bests excluding the current session
        let priorSessions = allSessions.filter { $0.id != session.id }
        var priorBestByKey: [String: Double] = [:]
        for s in priorSessions {
            for exercise in s.workoutExercisesList {
                let key = exercise.stableKey
                let usePlanned = exercise.progressiveOverloadApplied
                for set in exercise.setsList where set.isCompleted {
                    let w = usePlanned ? set.plannedWeight : set.actualWeight
                    let r = usePlanned ? set.plannedReps : set.actualReps
                    guard w > 0, r > 0 else { continue }
                    let est = w * (1.0 + Double(r) / 30.0)
                    priorBestByKey[key] = max(priorBestByKey[key] ?? 0, est)
                }
            }
        }

        // Find new PRs in the current session
        var prs: [PRSummary] = []
        for exercise in session.workoutExercisesList {
            let key = exercise.stableKey
            let usePlanned = exercise.progressiveOverloadApplied
            // No prior history means no baseline — a first-time exercise
            // trivially "beats" nothing and must not count as a PR.
            guard let priorBest = priorBestByKey[key] else { continue }

            var bestSetFor1RM: (w: Double, r: Int, est: Double)?
            for set in exercise.setsList where set.isCompleted {
                let w = usePlanned ? set.plannedWeight : set.actualWeight
                let r = usePlanned ? set.plannedReps : set.actualReps
                guard w > 0, r > 0 else { continue }
                let est = w * (1.0 + Double(r) / 30.0)
                if est > (bestSetFor1RM?.est ?? 0) {
                    bestSetFor1RM = (w, r, est)
                }
            }

            guard let best = bestSetFor1RM, best.est > priorBest else { continue }
            prs.append(PRSummary(
                exerciseName: exercise.exerciseName,
                weightKg: best.w,
                reps: best.r
            ))
        }

        return prs
    }
}
