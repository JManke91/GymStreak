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

    // MARK: - Public API

    /// Builds the AI Coach input for a workout analysis.
    /// - Parameters:
    ///   - session: The workout session to analyse.
    ///   - locale: The user's current locale.
    ///   - modelContext: The SwiftData context to query history from.
    /// - Returns: A `WorkoutAnalysisInput` or `nil` if insufficient data.
    func buildInput(
        session: WorkoutSession,
        locale: Locale,
        modelContext: ModelContext
    ) -> WorkoutAnalysisInput? {
        // Gate: minimum completed sets
        let completedSets = session.workoutExercisesList
            .flatMap(\.setsList)
            .filter(\.isCompleted)
        guard completedSets.count >= Self.minimumSetsThreshold else { return nil }

        // Find the previous session with the same routine name
        guard let previousSession = findPreviousSession(
            routineName: session.routineName,
            before: session.startTime,
            excludingId: session.id,
            modelContext: modelContext
        ) else { return nil }

        // Build per-exercise comparison data
        let progressService = ExerciseProgressService(modelContext: modelContext)
        let comparisonResults = progressService.compareWithPrevious(workout: session)
        let sortedExercises = session.workoutExercisesList.sorted(by: { $0.order < $1.order })

        var exerciseInputs: [WorkoutAnalysisExerciseInput] = []
        for (index, exercise) in sortedExercises.enumerated() {
            let comparison = index < comparisonResults.count ? comparisonResults[index] : nil
            let input = buildExerciseInput(exercise: exercise, comparison: comparison)
            exerciseInputs.append(input)
        }

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
        let previousVolume = computeVolume(session: previousSession)
        let previousSetsCount = previousSession.workoutExercisesList
            .flatMap(\.setsList)
            .filter(\.isCompleted)
            .count

        return WorkoutAnalysisInput(
            locale: locale.identifier,
            routineName: session.routineName,
            daysSincePrevious: daysSincePrevious,
            currentDurationMinutes: Int(session.duration / 60),
            currentTotalVolumeKg: session.totalVolume,
            currentTotalSets: completedSets.count,
            currentCompletionPercentage: session.completionPercentage,
            previousTotalVolumeKg: previousVolume,
            previousTotalSets: previousSetsCount,
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
        let completedSets = exercise.setsList.filter(\.isCompleted)
        let sortedSets = exercise.setsList.sorted(by: { $0.order < $1.order })

        let currentVolume = completedSets.reduce(0.0) { total, set in
            let w = usePlanned ? set.plannedWeight : set.actualWeight
            let r = usePlanned ? set.plannedReps : set.actualReps
            return total + (w * Double(r))
        }

        let currentTotalReps = completedSets.reduce(0) { total, set in
            total + (usePlanned ? set.plannedReps : set.actualReps)
        }

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
            currentVolumeKg: currentVolume,
            currentSetsCount: completedSets.count,
            currentTotalReps: currentTotalReps,
            isFirstTime: isFirstTime,
            volumeDeltaKg: comparison?.volumeDelta,
            sets: setInputs
        )
    }

    private func computeVolume(session: WorkoutSession) -> Double {
        session.workoutExercisesList.reduce(0.0) { total, exercise in
            let usePlanned = exercise.progressiveOverloadApplied
            return total + exercise.setsList.filter(\.isCompleted).reduce(0.0) { subtotal, set in
                let w = usePlanned ? set.plannedWeight : set.actualWeight
                let r = usePlanned ? set.plannedReps : set.actualReps
                return subtotal + (w * Double(r))
            }
        }
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
            let priorBest = priorBestByKey[key] ?? 0

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
