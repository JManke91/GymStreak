//
//  ExerciseComparisonBuilder.swift
//  GymStreak
//

import Foundation

/// Turns the workout in front of the user, plus its already-resolved history, into the
/// per-exercise comparison rows shown on the save sheet and the workout detail screen.
///
/// **The split from `PreviousPerformanceResolver` is the point** (audit P1.6). Only the
/// *previous* side is an unbounded history scan, and that half runs on
/// `SwiftDataHistorySnapshotStore`'s executor. This half reads nothing but the current
/// workout — a graph the caller already holds on the main actor and the screen renders
/// anyway — which is what lets the comparison work for a workout that has not been
/// committed to the store yet, without betting on cross-context visibility of unsaved
/// changes (see `PreviousPerformanceLookup`).
///
/// Pure and isolation-agnostic; never add `@MainActor`.
enum ExerciseComparisonBuilder {

    /// Describes `workout` for the off-main resolver: values only, no `@Model`.
    static func makeLookup(workout: WorkoutSession) -> PreviousPerformanceLookup {
        PreviousPerformanceLookup(
            before: workout.startTime,
            routineId: workout.routine?.id,
            exercises: workout.workoutExercisesList
                .sorted { $0.order < $1.order }
                .map {
                    PreviousPerformanceLookup.Query(
                        workoutExerciseId: $0.id,
                        exerciseName: $0.exerciseName,
                        exerciseId: $0.exerciseId,
                        loadBehavior: $0.loadBehavior,
                        routineExerciseId: $0.routineExerciseId
                    )
                }
        )
    }

    /// Combines the current workout with the resolved predecessors, in `order`.
    ///
    /// Exercises absent from `previousPerformances` come back as `isFirstTime`, which is
    /// also what an empty dictionary produces — so callers that cannot distinguish "no
    /// history" from "the lookup failed" must not pass a failed lookup's result here.
    static func build(
        workout: WorkoutSession,
        previousPerformances: [UUID: PreviousExercisePerformance]
    ) -> [ExerciseComparisonResult] {
        workout.workoutExercisesList
            .sorted { $0.order < $1.order }
            .map { exercise in
                build(
                    exercise: exercise,
                    previous: previousPerformances[exercise.id],
                    bodyWeightKg: workout.bodyWeightKg
                )
            }
    }

    // MARK: - Private

    private static func build(
        exercise: WorkoutExercise,
        previous: PreviousExercisePerformance?,
        bodyWeightKg: Double?
    ) -> ExerciseComparisonResult {
        let usePlanned = exercise.progressiveOverloadApplied
        let sortedSets = exercise.setsList.sorted { $0.order < $1.order }
        let completedSets = exercise.setsList.filter(\.isCompleted)

        let setComparisons = sortedSets.enumerated().map { index, set in
            // Sets are compared by position: set 1 against set 1. A previous workout
            // with fewer sets simply leaves the extra ones without a counterpart.
            let previousSet = previous?.sets.indices.contains(index) == true
                ? previous?.sets[index]
                : nil
            return ExerciseComparisonResult.CurrentExercisePerformance.SetComparison(
                setNumber: index + 1,
                currentReps: usePlanned ? set.plannedReps : set.actualReps,
                currentWeight: usePlanned ? set.plannedWeight : set.actualWeight,
                previousReps: previousSet?.reps,
                previousWeight: previousSet?.weight,
                isCompleted: set.isCompleted
            )
        }

        let totalVolume = completedSets.reduce(0.0) { subtotal, set in
            let weight = usePlanned ? set.plannedWeight : set.actualWeight
            let reps = usePlanned ? set.plannedReps : set.actualReps
            return subtotal + (weight * Double(reps))
        }

        return ExerciseComparisonResult(
            workoutExerciseId: exercise.id,
            exerciseName: exercise.exerciseName,
            loadBehavior: exercise.loadBehavior,
            currentPerformance: ExerciseComparisonResult.CurrentExercisePerformance(
                sets: setComparisons,
                totalVolume: totalVolume,
                effectiveTotalVolume: ExerciseLoadMetrics.effectiveVolume(
                    from: completedSets,
                    usePlannedValues: usePlanned,
                    behavior: exercise.loadBehavior,
                    bodyWeightKg: bodyWeightKg
                ),
                completedSetsCount: completedSets.count,
                totalReps: completedSets.reduce(0) { $0 + (usePlanned ? $1.plannedReps : $1.actualReps) }
            ),
            previousPerformance: previous
        )
    }
}
