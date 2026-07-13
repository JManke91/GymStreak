//
//  ExerciseProgressService.swift
//  GymStreak
//

import Foundation
import SwiftData

/// Service for fetching and aggregating exercise progress data across workout sessions
@MainActor
class ExerciseProgressService: ExerciseProgressProviding {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Progress Data for Charts

    /// Fetches progress data for a specific exercise within a timeframe
    /// - Parameters:
    ///   - exerciseName: The name of the exercise (case-insensitive match)
    ///   - timeframe: The timeframe to fetch data for
    /// - Returns: ExerciseProgressData containing all data points for charting
    func fetchProgressData(
        for exerciseName: String,
        exerciseId: UUID? = nil,
        timeframe: ChartTimeframe
    ) -> ExerciseProgressData {
        let startDate = timeframe.startDate
        let nameIsUnique = isLiveNameUnique(exerciseName)
        let loadBehavior = loadBehavior(for: exerciseId, exerciseName: exerciseName)

        // Fetch all completed workout sessions within the timeframe
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.startTime >= startDate && session.endTime != nil
            },
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )

        do {
            let sessions = try modelContext.fetch(descriptor)
            let matchedBySession = sessions.map { session in
                (session, session.workoutExercisesList.filter {
                    Self.matches($0, exerciseId: exerciseId, exerciseName: exerciseName, nameIsUnique: nameIsUnique)
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
                        ? calculateEstimated1RM(
                            from: completedSets,
                            usePlannedValues: usePlanned,
                            behavior: loadBehavior,
                            bodyWeightKg: session.bodyWeightKg
                        )
                        : 0
                    sessionBest1RM = max(sessionBest1RM, estimated1RM)
                }

                guard hasCompletedSets else { continue }

                let dataPoint = ExerciseProgressDataPoint(
                    date: session.startTime,
                    maxWeight: sessionMaxWeight,
                    estimated1RM: sessionBest1RM,
                    totalVolume: sessionTotalVolume,
                    totalSets: sessionTotalSets,
                    totalReps: sessionTotalReps,
                    workoutSessionId: session.id
                )

                dataPoints.append(dataPoint)
            }

            return ExerciseProgressData(
                exerciseName: exerciseName,
                dataPoints: dataPoints,
                loadBehavior: loadBehavior,
                usesEffectiveLoad: usesEffectiveLoad
            )
        } catch {
            print("Error fetching progress data: \(error)")
            return ExerciseProgressData(
                exerciseName: exerciseName,
                dataPoints: [],
                loadBehavior: loadBehavior,
                usesEffectiveLoad: false
            )
        }
    }

    // MARK: - Previous Performance Lookup

    /// Finds the previous time an exercise was performed before a given date
    /// - Parameters:
    ///   - exerciseName: The name of the exercise (case-insensitive match)
    ///   - date: The date to look before
    /// - Returns: PreviousExercisePerformance if found, nil otherwise
    func previousPerformance(
        for exerciseName: String,
        exerciseId: UUID? = nil,
        before date: Date,
        expectedLoadBehavior: ExerciseLoadBehavior? = nil,
        routineId: UUID? = nil,
        occurrenceIndex: Int = 0,
        routineExerciseId: UUID? = nil
    ) -> PreviousExercisePerformance? {
        let nameIsUnique = isLiveNameUnique(exerciseName)

        // Fetch completed sessions before the given date, most recent first
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.startTime < date && session.endTime != nil
            },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )

        do {
            let sessions = try modelContext.fetch(descriptor)

            // Find the most recent same-routine session containing the same
            // ordered occurrence. The occurrence index is the legacy identity
            // for workouts recorded before routine-slot ids were snapshotted.
            for session in sessions {
                let matchingExercises = session.workoutExercisesList
                    .filter {
                    Self.matches($0, exerciseId: exerciseId, exerciseName: exerciseName, nameIsUnique: nameIsUnique)
                        && (expectedLoadBehavior == nil || $0.loadBehavior == expectedLoadBehavior)
                    }
                    .sorted { $0.order < $1.order }

                let exercise: WorkoutExercise
                if let routineExerciseId,
                   let exactMatch = matchingExercises.first(where: { $0.routineExerciseId == routineExerciseId }) {
                    exercise = exactMatch
                } else {
                    // Occurrence order is only meaningful inside a proven
                    // routine context. If the relationship no longer exists,
                    // a display-name match could silently join two routines
                    // with the same name, so legacy comparison stays empty.
                    guard let routineId, session.routine?.id == routineId else { continue }
                    let legacyMatches = routineExerciseId == nil
                        ? matchingExercises
                        : matchingExercises.filter { $0.routineExerciseId == nil }
                    guard legacyMatches.indices.contains(occurrenceIndex) else { continue }
                    exercise = legacyMatches[occurrenceIndex]
                }

                let usePlanned = exercise.progressiveOverloadApplied
                let sets = exercise.setsList.sorted(by: { $0.order < $1.order }).map { set in
                    PreviousExercisePerformance.SetPerformance(
                        reps: usePlanned ? set.plannedReps : set.actualReps,
                        weight: usePlanned ? set.plannedWeight : set.actualWeight,
                        isCompleted: set.isCompleted
                    )
                }

                return PreviousExercisePerformance(
                    date: session.startTime,
                    routineName: session.routineName,
                    sets: sets,
                    effectiveTotalVolume: effectiveVolume(
                        from: exercise.setsList.filter(\.isCompleted),
                        usePlannedValues: usePlanned,
                        behavior: exercise.loadBehavior,
                        bodyWeightKg: session.bodyWeightKg
                    )
                )
            }

            return nil
        } catch {
            print("Error fetching previous performance: \(error)")
            return nil
        }
    }

    // MARK: - Comparison for Workout Detail View

    /// Compares current workout exercises with their previous performances
    /// - Parameter workout: The current workout session to compare
    /// - Returns: Array of comparison results for each exercise
    func compareWithPrevious(workout: WorkoutSession) -> [ExerciseComparisonResult] {
        var results: [ExerciseComparisonResult] = []
        let sortedExercises = workout.workoutExercisesList.sorted(by: { $0.order < $1.order })

        for exercise in sortedExercises {
            let matchingCurrentExercises = sortedExercises.filter {
                Self.matches(
                    $0,
                    exerciseId: exercise.exerciseId,
                    exerciseName: exercise.exerciseName,
                    nameIsUnique: isLiveNameUnique(exercise.exerciseName)
                ) && $0.loadBehavior == exercise.loadBehavior
            }
            let occurrenceIndex = matchingCurrentExercises.firstIndex { $0.id == exercise.id } ?? 0
            let previous = previousPerformance(
                for: exercise.exerciseName,
                exerciseId: exercise.exerciseId,
                before: workout.startTime,
                expectedLoadBehavior: exercise.loadBehavior,
                routineId: workout.routine?.id,
                occurrenceIndex: occurrenceIndex,
                routineExerciseId: exercise.routineExerciseId
            )

            let completedSets = exercise.setsList.filter(\.isCompleted)
            let sortedSets = exercise.setsList.sorted(by: { $0.order < $1.order })
            let usePlanned = exercise.progressiveOverloadApplied

            // Build set comparisons
            var setComparisons: [ExerciseComparisonResult.CurrentExercisePerformance.SetComparison] = []

            for (index, set) in sortedSets.enumerated() {
                // Get corresponding previous set if available
                let previousSet = previous?.sets.indices.contains(index) == true ? previous?.sets[index] : nil

                let reps = usePlanned ? set.plannedReps : set.actualReps
                let weight = usePlanned ? set.plannedWeight : set.actualWeight

                let comparison = ExerciseComparisonResult.CurrentExercisePerformance.SetComparison(
                    setNumber: index + 1,
                    currentReps: reps,
                    currentWeight: weight,
                    previousReps: previousSet?.reps,
                    previousWeight: previousSet?.weight,
                    isCompleted: set.isCompleted
                )
                setComparisons.append(comparison)
            }

            let totalVolume = completedSets.reduce(0.0) { subtotal, set in
                let w = usePlanned ? set.plannedWeight : set.actualWeight
                let r = usePlanned ? set.plannedReps : set.actualReps
                return subtotal + (w * Double(r))
            }
            let totalReps = completedSets.reduce(0) { $0 + (usePlanned ? $1.plannedReps : $1.actualReps) }
            let effectiveTotalVolume = effectiveVolume(
                from: completedSets,
                usePlannedValues: usePlanned,
                behavior: exercise.loadBehavior,
                bodyWeightKg: workout.bodyWeightKg
            )

            let currentPerformance = ExerciseComparisonResult.CurrentExercisePerformance(
                sets: setComparisons,
                totalVolume: totalVolume,
                effectiveTotalVolume: effectiveTotalVolume,
                completedSetsCount: completedSets.count,
                totalReps: totalReps
            )

            let result = ExerciseComparisonResult(
                exerciseName: exercise.exerciseName,
                loadBehavior: exercise.loadBehavior,
                currentPerformance: currentPerformance,
                previousPerformance: previous
            )

            results.append(result)
        }

        return results
    }

    // MARK: - Matching

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
        if let exerciseId {
            if exercise.exerciseId == exerciseId { return true }
            if nameIsUnique,
               exercise.exerciseId == nil,
               exercise.exerciseName.lowercased() == exerciseName.lowercased() {
                return true
            }
            return false
        }
        if nameIsUnique {
            return exercise.exerciseName.lowercased() == exerciseName.lowercased()
        }
        return false
    }

    /// Whether `name` is unique (case-insensitive) among the user's live `Exercise` library.
    /// Drives the legacy-row name-fallback in `matches(_:exerciseId:exerciseName:nameIsUnique:)`.
    func isLiveNameUnique(_ name: String) -> Bool {
        let target = name.lowercased()
        do {
            let exercises = try modelContext.fetch(FetchDescriptor<Exercise>())
            return exercises.filter { $0.name.lowercased() == target }.count <= 1
        } catch {
            return true
        }
    }

    private func loadBehavior(for exerciseId: UUID?, exerciseName: String) -> ExerciseLoadBehavior {
        do {
            let exercises = try modelContext.fetch(FetchDescriptor<Exercise>())
            if let exerciseId, let exercise = exercises.first(where: { $0.id == exerciseId }) {
                return exercise.loadBehavior
            }
            return exercises.first { $0.name.caseInsensitiveCompare(exerciseName) == .orderedSame }?.loadBehavior ?? .resistance
        } catch {
            return .resistance
        }
    }

    // MARK: - Private Helpers

    /// Calculates estimated 1RM using Epley formula
    /// Uses the best set (highest estimated 1RM) from the given sets
    private func calculateEstimated1RM(
        from sets: [WorkoutSet],
        usePlannedValues: Bool = false,
        behavior: ExerciseLoadBehavior,
        bodyWeightKg: Double?
    ) -> Double {
        guard !sets.isEmpty else { return 0 }

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

            // Epley formula: weight * (1 + reps/30)
            let estimated = ExerciseLoadMetrics.estimatedOneRepMax(weight: weight, reps: reps)
            best1RM = max(best1RM, estimated)
        }

        return best1RM
    }

    private func effectiveVolume(
        from sets: [WorkoutSet],
        usePlannedValues: Bool,
        behavior: ExerciseLoadBehavior,
        bodyWeightKg: Double?
    ) -> Double? {
        if behavior.isCounterweightAssistance && bodyWeightKg == nil {
            return nil
        }
        return sets.reduce(0) { total, set in
            let enteredWeight = usePlannedValues ? set.plannedWeight : set.actualWeight
            let reps = usePlannedValues ? set.plannedReps : set.actualReps
            let effectiveWeight = ExerciseLoadMetrics.effectiveWeight(
                enteredWeight: enteredWeight,
                behavior: behavior,
                bodyWeightKg: bodyWeightKg
            ) ?? 0
            return total + effectiveWeight * Double(reps)
        }
    }
}
