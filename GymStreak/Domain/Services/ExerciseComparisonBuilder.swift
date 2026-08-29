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
/// **Every read of the `@Model` graph happens in `makeSnapshot`, and nothing reads it
/// afterwards.** `ExerciseProgressService.compareWithPrevious` awaits the off-main history
/// scan between the two halves, and the session can be deleted during that await — the save
/// sheet compares `WorkoutViewModel.currentSession`, which `cancelWorkout()` discards. A
/// property read on a deleted `@Model` is an uncatchable SwiftData `fatalError`, so `build`
/// is handed values only. See `docs/history-delete-race.md`.
///
/// Pure and isolation-agnostic; never add `@MainActor`.
enum ExerciseComparisonBuilder {

    // MARK: - Snapshot

    /// The current workout reduced to values: what the resolver needs to find predecessors,
    /// and what `build` needs to assemble the rows.
    struct WorkoutSnapshot: Sendable {
        let lookup: PreviousPerformanceLookup
        /// One entry per exercise, in `WorkoutExercise.order`.
        let exercises: [ExerciseSnapshot]
    }

    /// One exercise of the current workout, with its per-set values and the aggregates that
    /// depend only on this side of the comparison.
    struct ExerciseSnapshot: Sendable {
        let workoutExerciseId: UUID
        let exerciseName: String
        let loadBehavior: ExerciseLoadBehavior
        /// Sorted by `WorkoutSet.order`, already resolved to planned-or-actual values.
        let sets: [SetSnapshot]
        let totalVolume: Double
        let effectiveTotalVolume: Double?
        let completedSetsCount: Int
        let totalReps: Int
    }

    struct SetSnapshot: Sendable {
        let reps: Int
        let weight: Double
        let isCompleted: Bool
    }

    /// Describes `workout` for both halves: values only, no `@Model`.
    static func makeSnapshot(workout: WorkoutSession) -> WorkoutSnapshot {
        let ordered = workout.workoutExercisesList.sorted { $0.order < $1.order }
        let bodyWeightKg = workout.bodyWeightKg

        return WorkoutSnapshot(
            lookup: PreviousPerformanceLookup(
                before: workout.startTime,
                routineId: workout.routine?.id,
                exercises: ordered.map {
                    PreviousPerformanceLookup.Query(
                        workoutExerciseId: $0.id,
                        exerciseName: $0.exerciseName,
                        exerciseId: $0.exerciseId,
                        loadBehavior: $0.loadBehavior,
                        routineExerciseId: $0.routineExerciseId
                    )
                }
            ),
            exercises: ordered.map { snapshot(exercise: $0, bodyWeightKg: bodyWeightKg) }
        )
    }

    // MARK: - Build

    /// Combines the snapshotted workout with the resolved predecessors, in `order`.
    ///
    /// Exercises absent from `previousPerformances` come back as `isFirstTime`, which is
    /// also what an empty dictionary produces — so callers that cannot distinguish "no
    /// history" from "the lookup failed" must not pass a failed lookup's result here.
    static func build(
        snapshot: WorkoutSnapshot,
        previousPerformances: [UUID: PreviousExercisePerformance]
    ) -> [ExerciseComparisonResult] {
        snapshot.exercises.map { exercise in
            build(exercise: exercise, previous: previousPerformances[exercise.workoutExerciseId])
        }
    }

    // MARK: - Private

    private static func snapshot(
        exercise: WorkoutExercise,
        bodyWeightKg: Double?
    ) -> ExerciseSnapshot {
        let usePlanned = exercise.progressiveOverloadApplied
        let sortedSets = exercise.setsList.sorted { $0.order < $1.order }
        let completedSets = exercise.setsList.filter(\.isCompleted)

        return ExerciseSnapshot(
            workoutExerciseId: exercise.id,
            exerciseName: exercise.exerciseName,
            loadBehavior: exercise.loadBehavior,
            sets: sortedSets.map {
                SetSnapshot(
                    reps: usePlanned ? $0.plannedReps : $0.actualReps,
                    weight: usePlanned ? $0.plannedWeight : $0.actualWeight,
                    isCompleted: $0.isCompleted
                )
            },
            totalVolume: completedSets.reduce(0.0) { subtotal, set in
                let weight = usePlanned ? set.plannedWeight : set.actualWeight
                let reps = usePlanned ? set.plannedReps : set.actualReps
                return subtotal + (weight * Double(reps))
            },
            effectiveTotalVolume: ExerciseLoadMetrics.effectiveVolume(
                from: completedSets,
                usePlannedValues: usePlanned,
                behavior: exercise.loadBehavior,
                bodyWeightKg: bodyWeightKg
            ),
            completedSetsCount: completedSets.count,
            totalReps: completedSets.reduce(0) { $0 + (usePlanned ? $1.plannedReps : $1.actualReps) }
        )
    }

    private static func build(
        exercise: ExerciseSnapshot,
        previous: PreviousExercisePerformance?
    ) -> ExerciseComparisonResult {
        let setComparisons = exercise.sets.enumerated().map { index, set in
            // Sets are compared by position: set 1 against set 1. A previous workout
            // with fewer sets simply leaves the extra ones without a counterpart.
            let previousSet = previous?.sets.indices.contains(index) == true
                ? previous?.sets[index]
                : nil
            return ExerciseComparisonResult.CurrentExercisePerformance.SetComparison(
                setNumber: index + 1,
                currentReps: set.reps,
                currentWeight: set.weight,
                previousReps: previousSet?.reps,
                previousWeight: previousSet?.weight,
                isCompleted: set.isCompleted
            )
        }

        return ExerciseComparisonResult(
            workoutExerciseId: exercise.workoutExerciseId,
            exerciseName: exercise.exerciseName,
            loadBehavior: exercise.loadBehavior,
            currentPerformance: ExerciseComparisonResult.CurrentExercisePerformance(
                sets: setComparisons,
                totalVolume: exercise.totalVolume,
                effectiveTotalVolume: exercise.effectiveTotalVolume,
                completedSetsCount: exercise.completedSetsCount,
                totalReps: exercise.totalReps
            ),
            previousPerformance: previous
        )
    }
}
