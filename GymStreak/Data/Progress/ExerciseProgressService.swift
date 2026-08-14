//
//  ExerciseProgressService.swift
//  GymStreak
//

import Foundation
import SwiftData

/// Service for the main-actor exercise comparisons shown while saving a workout and in
/// a workout's detail screen.
///
/// The exercise **chart** no longer goes through here: its whole-history aggregation
/// moved to `SwiftDataHistorySnapshotStore` behind `HistorySnapshotProviding`, with the
/// pure logic in `ExerciseProgressAggregator` (audit P1.2). What remains is the
/// comparison surface, which operates on a caller-supplied main-context `WorkoutSession`
/// and therefore cannot cross an actor boundary as-is.
@MainActor
class ExerciseProgressService: ExerciseProgressProviding {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
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
                    ExerciseProgressAggregator.matches($0, exerciseId: exerciseId, exerciseName: exerciseName, nameIsUnique: nameIsUnique)
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
                ExerciseProgressAggregator.matches(
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

    /// Whether `name` is unique (case-insensitive) among the user's live `Exercise` library.
    /// Drives the legacy-row name fallback in `ExerciseProgressAggregator.matches`.
    private func isLiveNameUnique(_ name: String) -> Bool {
        do {
            let exercises = try modelContext.fetch(FetchDescriptor<Exercise>())
            return ExerciseProgressAggregator.isNameUnique(name, in: exercises)
        } catch {
            return true
        }
    }

    // MARK: - Private Helpers

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
