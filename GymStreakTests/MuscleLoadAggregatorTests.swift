//
//  MuscleLoadAggregatorTests.swift
//  GymStreakTests
//
//  MuscleLoadAggregator is pure aggregation over in-memory models — the denormalized history
//  copy for a workout, the live exercise library for a routine. No ModelContext/persistence
//  needed, just plain object construction.
//

import Testing
import Foundation
@testable import GymStreak

@MainActor
struct MuscleLoadAggregatorTests {

    // MARK: - Fixtures

    /// Builds one recorded exercise with `completedSets` completed sets followed by
    /// `uncompletedSets` skipped ones.
    private func makeExercise(
        name: String,
        muscleGroups: [String],
        order: Int,
        completedSets: Int,
        uncompletedSets: Int = 0
    ) -> WorkoutExercise {
        let exercise = WorkoutExercise(exerciseName: name, muscleGroups: muscleGroups, order: order)
        exercise.sets = (0..<(completedSets + uncompletedSets)).map { index in
            let set = WorkoutSet(
                plannedReps: 10,
                actualReps: 10,
                plannedWeight: 50,
                actualWeight: 50,
                restTime: 60,
                order: index
            )
            set.isCompleted = index < completedSets
            set.workoutExercise = exercise
            return set
        }
        return exercise
    }

    private func makeSession(_ exercises: [WorkoutExercise]) -> WorkoutSession {
        let session = WorkoutSession(routine: nil)
        session.routineName = "Push Day"
        session.endTime = session.startTime.addingTimeInterval(3600)
        session.workoutExercises = exercises
        for exercise in exercises { exercise.workoutSession = session }
        return session
    }

    // MARK: - Key mapping

    @Test
    func everyMuscleGroupKeyResolvesOrIsExplicitlyUnmapped() {
        let expected: [String: MuscleMapRegion?] = [
            "Upper Back": .trapezius,
            "Shoulders": .shoulders,
            "Front Delts": .shoulders,
            "Side Delts": .shoulders,
            "Rear Delts": .shoulders,
            "Chest": .chest,
            "Upper Chest": .chest,
            "Biceps": .biceps,
            "Triceps": .triceps,
            "Forearms": .forearms,
            "Abs": .abs,
            "Obliques": .abs,
            "Lats": .back,
            "Lower Back": .lowerBack,
            "Glutes": .glutes,
            "Quadriceps": .quadriceps,
            "Hip Flexors": .quadriceps,
            "Hamstrings": .hamstrings,
            "Calves": .calves,
            "General": MuscleMapRegion?.none,
        ]

        // Guards against a key being added to the catalogue without a region.
        #expect(Set(MuscleGroups.allKeys + ["General"]) == Set(expected.keys))
        for (key, region) in expected {
            #expect(MuscleMapRegion(muscleGroupKey: key) == region, "key \(key)")
        }
    }

    // MARK: - Workout aggregation (completed sets, denormalized copy)

    @Test
    func firstMuscleGroupIsPrimaryAndTheRestAreSecondary() {
        let session = makeSession([
            makeExercise(
                name: "Bench Press",
                muscleGroups: ["Chest", "Triceps", "Front Delts"],
                order: 0,
                completedSets: 3
            )
        ])

        let loads = MuscleLoadAggregator.aggregate(session: session)

        #expect(loads[.chest]?.engagement == .primary)
        #expect(loads[.chest]?.setCount == 3)
        #expect(loads[.triceps]?.engagement == .secondary)
        #expect(loads[.shoulders]?.engagement == .secondary)
        // Supporting work records the exercise but adds no sets.
        #expect(loads[.triceps]?.setCount == 0)
        #expect(loads[.triceps]?.exerciseNames == ["Bench Press"])
        #expect(loads.count == 3)
    }

    @Test
    func primaryWinsOverSecondaryForTheSameRegion() {
        let session = makeSession([
            makeExercise(name: "Bench Press", muscleGroups: ["Chest", "Triceps"], order: 0, completedSets: 3),
            makeExercise(name: "Triceps Pushdown", muscleGroups: ["Triceps"], order: 1, completedSets: 4),
        ])

        let loads = MuscleLoadAggregator.aggregate(session: session)

        #expect(loads[.triceps]?.engagement == .primary)
        // Only the exercise the region led contributes sets.
        #expect(loads[.triceps]?.setCount == 4)
        #expect(loads[.triceps]?.exerciseNames == ["Bench Press", "Triceps Pushdown"])
    }

    @Test
    func primaryWinsRegardlessOfExerciseOrder() {
        let session = makeSession([
            makeExercise(name: "Triceps Pushdown", muscleGroups: ["Triceps"], order: 0, completedSets: 4),
            makeExercise(name: "Bench Press", muscleGroups: ["Chest", "Triceps"], order: 1, completedSets: 3),
        ])

        let loads = MuscleLoadAggregator.aggregate(session: session)

        #expect(loads[.triceps]?.engagement == .primary)
        #expect(loads[.triceps]?.setCount == 4)
        #expect(loads[.triceps]?.exerciseNames == ["Triceps Pushdown", "Bench Press"])
    }

    @Test
    func setsOfSeveralPrimaryExercisesAccumulate() {
        let session = makeSession([
            makeExercise(name: "Bench Press", muscleGroups: ["Chest"], order: 0, completedSets: 3),
            makeExercise(name: "Incline Press", muscleGroups: ["Upper Chest"], order: 1, completedSets: 2),
        ])

        let loads = MuscleLoadAggregator.aggregate(session: session)

        #expect(loads[.chest]?.setCount == 5)
        #expect(loads[.chest]?.exerciseNames == ["Bench Press", "Incline Press"])
    }

    @Test
    func keysCollapsingOntoOneRegionCountTheExerciseOnce() {
        let session = makeSession([
            makeExercise(
                name: "Overhead Press",
                muscleGroups: ["Shoulders", "Front Delts", "Triceps"],
                order: 0,
                completedSets: 3
            )
        ])

        let loads = MuscleLoadAggregator.aggregate(session: session)

        #expect(loads[.shoulders]?.engagement == .primary)
        #expect(loads[.shoulders]?.setCount == 3)
        #expect(loads[.shoulders]?.exerciseNames == ["Overhead Press"])
    }

    @Test
    func hipFlexorsLandOnQuadricepsAndGeneralHighlightsNothing() {
        let session = makeSession([
            makeExercise(name: "Leg Raise", muscleGroups: ["Hip Flexors", "General"], order: 0, completedSets: 3)
        ])

        let loads = MuscleLoadAggregator.aggregate(session: session)

        #expect(loads[.quadriceps]?.engagement == .primary)
        #expect(loads[.quadriceps]?.setCount == 3)
        #expect(loads.count == 1)
    }

    @Test
    func anUnmappedLeadingKeyDoesNotSwallowTheExercise() {
        let session = makeSession([
            makeExercise(name: "Sled Push", muscleGroups: ["General", "Quadriceps"], order: 0, completedSets: 3)
        ])

        let loads = MuscleLoadAggregator.aggregate(session: session)

        // The first *mapped* key leads, so the completed sets still land somewhere.
        #expect(loads[.quadriceps]?.engagement == .primary)
        #expect(loads[.quadriceps]?.setCount == 3)
    }

    @Test
    func uncompletedSetsAreExcludedFromTheCount() {
        let session = makeSession([
            makeExercise(name: "Squat", muscleGroups: ["Quadriceps"], order: 0, completedSets: 2, uncompletedSets: 3)
        ])

        let loads = MuscleLoadAggregator.aggregate(session: session)

        #expect(loads[.quadriceps]?.setCount == 2)
    }

    @Test
    func anExerciseWithoutCompletedSetsContributesNothing() {
        let session = makeSession([
            makeExercise(name: "Squat", muscleGroups: ["Quadriceps"], order: 0, completedSets: 3),
            makeExercise(name: "Calf Raise", muscleGroups: ["Calves"], order: 1, completedSets: 0, uncompletedSets: 3),
        ])

        let loads = MuscleLoadAggregator.aggregate(session: session)

        #expect(loads[.calves] == nil)
        #expect(loads.count == 1)
    }

    @Test
    func aSessionThatMapsToNothingYieldsAnEmptyResult() {
        let onlyGeneral = makeSession([
            makeExercise(name: "Mobility Flow", muscleGroups: ["General"], order: 0, completedSets: 3)
        ])
        #expect(MuscleLoadAggregator.aggregate(session: onlyGeneral).isEmpty)

        let empty = makeSession([])
        #expect(MuscleLoadAggregator.aggregate(session: empty).isEmpty)
    }

    // MARK: - Routine fixtures

    /// Builds one routine slot backed by a live library exercise with `plannedSets` planned sets.
    private func makeRoutineExercise(
        name: String,
        muscleGroups: [String],
        order: Int,
        plannedSets: Int
    ) -> RoutineExercise {
        let routineExercise = RoutineExercise(
            exercise: Exercise(name: name, muscleGroups: muscleGroups),
            order: order
        )
        routineExercise.sets = (0..<plannedSets).map {
            ExerciseSet(reps: 10, weight: 50, restTime: 60, order: $0)
        }
        return routineExercise
    }

    private func makeRoutine(_ routineExercises: [RoutineExercise]) -> Routine {
        let routine = Routine(name: "Push Day")
        routine.routineExercises = routineExercises
        return routine
    }

    // MARK: - Routine aggregation (planned sets, live library)

    @Test
    func routineReadsMuscleGroupsFromTheLiveExercise() {
        let routineExercise = makeRoutineExercise(
            name: "Bench Press",
            muscleGroups: ["Chest", "Triceps"],
            order: 0,
            plannedSets: 3
        )
        let routine = makeRoutine([routineExercise])

        #expect(MuscleLoadAggregator.aggregate(routine: routine)[.chest]?.engagement == .primary)

        // Re-tagging the library exercise changes the plan immediately — a routine describes what
        // will happen, so it has no denormalized copy to fall back on.
        routineExercise.exercise?.muscleGroups = ["Biceps"]
        let retagged = MuscleLoadAggregator.aggregate(routine: routine)

        #expect(retagged[.biceps]?.engagement == .primary)
        #expect(retagged[.biceps]?.setCount == 3)
        #expect(retagged[.chest] == nil)
        #expect(retagged.count == 1)
    }

    @Test
    func plannedSetsAreCountedWhetherOrNotTheyAreMarkedCompleted() {
        let routineExercise = makeRoutineExercise(
            name: "Squat",
            muscleGroups: ["Quadriceps"],
            order: 0,
            plannedSets: 4
        )
        // Nothing in a routine is completed; the flag exists on the model, so pin that it is
        // ignored rather than silently halving the plan.
        routineExercise.setsList.first?.isCompleted = true

        let loads = MuscleLoadAggregator.aggregate(routine: makeRoutine([routineExercise]))

        #expect(loads[.quadriceps]?.setCount == 4)
    }

    @Test
    func aRoutineSlotWithoutAnAttachedExerciseContributesNothing() {
        let unattached = RoutineExercise(order: 1)
        unattached.sets = [ExerciseSet(reps: 10, weight: 50, restTime: 60, order: 0)]

        let routine = makeRoutine([
            makeRoutineExercise(name: "Squat", muscleGroups: ["Quadriceps"], order: 0, plannedSets: 3),
            unattached,
        ])

        let loads = MuscleLoadAggregator.aggregate(routine: routine)

        #expect(loads[.quadriceps]?.setCount == 3)
        #expect(loads.count == 1)
    }

    @Test
    func aRoutineExerciseWithoutPlannedSetsContributesNothing() {
        let routine = makeRoutine([
            makeRoutineExercise(name: "Squat", muscleGroups: ["Quadriceps"], order: 0, plannedSets: 3),
            makeRoutineExercise(name: "Calf Raise", muscleGroups: ["Calves"], order: 1, plannedSets: 0),
        ])

        let loads = MuscleLoadAggregator.aggregate(routine: routine)

        #expect(loads[.calves] == nil)
        #expect(loads.count == 1)
    }

    @Test
    func alternativeExercisesAreNotAggregated() {
        let routineExercise = makeRoutineExercise(
            name: "Bench Press",
            muscleGroups: ["Chest"],
            order: 0,
            plannedSets: 3
        )
        let alternative = RoutineExerciseAlternative(
            exercise: Exercise(name: "Leg Press", muscleGroups: ["Quadriceps"]),
            order: 0
        )
        alternative.sets = [AlternativeExerciseSet(reps: 10, weight: 100, restTime: 60, order: 0)]
        routineExercise.alternatives = [alternative]

        let loads = MuscleLoadAggregator.aggregate(routine: makeRoutine([routineExercise]))

        // The user performs the exercise *or* an alternative, never both.
        #expect(loads[.chest]?.setCount == 3)
        #expect(loads[.quadriceps] == nil)
        #expect(loads.count == 1)
    }

    @Test
    func routinePrimaryWinsOverSecondaryAcrossExercises() {
        let routine = makeRoutine([
            makeRoutineExercise(name: "Bench Press", muscleGroups: ["Chest", "Triceps"], order: 0, plannedSets: 3),
            makeRoutineExercise(name: "Triceps Pushdown", muscleGroups: ["Triceps"], order: 1, plannedSets: 4),
        ])

        let loads = MuscleLoadAggregator.aggregate(routine: routine)

        #expect(loads[.triceps]?.engagement == .primary)
        #expect(loads[.triceps]?.setCount == 4)
        #expect(loads[.triceps]?.exerciseNames == ["Bench Press", "Triceps Pushdown"])
    }

    @Test
    func routineKeysCollapsingOntoOneRegionCountTheExerciseOnce() {
        let routine = makeRoutine([
            makeRoutineExercise(
                name: "Overhead Press",
                muscleGroups: ["Shoulders", "Front Delts", "Triceps"],
                order: 0,
                plannedSets: 3
            )
        ])

        let loads = MuscleLoadAggregator.aggregate(routine: routine)

        #expect(loads[.shoulders]?.engagement == .primary)
        #expect(loads[.shoulders]?.setCount == 3)
        #expect(loads[.shoulders]?.exerciseNames == ["Overhead Press"])
    }

    @Test
    func routineExerciseNamesFollowTheRoutineOrder() {
        // Stored back-to-front, so a result in array order would fail this.
        let routine = makeRoutine([
            makeRoutineExercise(name: "Incline Press", muscleGroups: ["Upper Chest"], order: 1, plannedSets: 2),
            makeRoutineExercise(name: "Bench Press", muscleGroups: ["Chest"], order: 0, plannedSets: 3),
        ])

        let loads = MuscleLoadAggregator.aggregate(routine: routine)

        #expect(loads[.chest]?.exerciseNames == ["Bench Press", "Incline Press"])
        #expect(loads[.chest]?.setCount == 5)
    }

    @Test
    func aRoutineThatMapsToNothingYieldsAnEmptyResult() {
        let onlyGeneral = makeRoutine([
            makeRoutineExercise(name: "Mobility Flow", muscleGroups: ["General"], order: 0, plannedSets: 3)
        ])
        #expect(MuscleLoadAggregator.aggregate(routine: onlyGeneral).isEmpty)

        #expect(MuscleLoadAggregator.aggregate(routine: makeRoutine([])).isEmpty)
    }
}
