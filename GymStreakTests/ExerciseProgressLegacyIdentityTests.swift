import Foundation
import SwiftData
import Testing
@testable import GymStreak

extension ExerciseProgressServiceTests {
    @Test
    func duplicateRoutineNamesDoNotCrossCompare() async throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Biceps Curls")
        let targetRoutine = Routine(name: "Pull")
        let otherRoutine = Routine(name: "Pull")
        context.insert(exercise)
        context.insert(targetRoutine)
        context.insert(otherRoutine)

        let targetPrevious = WorkoutSession(routine: targetRoutine)
        targetPrevious.startTime = Date(timeIntervalSince1970: 1_000)
        targetPrevious.endTime = Date(timeIntervalSince1970: 1_100)
        context.insert(targetPrevious)
        addPerformance(exercise, weight: 20, reps: 5, order: 0, to: targetPrevious, context: context)

        let otherPrevious = WorkoutSession(routine: otherRoutine)
        otherPrevious.startTime = Date(timeIntervalSince1970: 1_500)
        otherPrevious.endTime = Date(timeIntervalSince1970: 1_600)
        context.insert(otherPrevious)
        addPerformance(exercise, weight: 13, reps: 12, order: 0, to: otherPrevious, context: context)

        let current = WorkoutSession(routine: targetRoutine)
        current.startTime = Date(timeIntervalSince1970: 2_000)
        current.endTime = Date(timeIntervalSince1970: 2_100)
        context.insert(current)
        addPerformance(exercise, weight: 21, reps: 5, order: 0, to: current, context: context)
        try context.save()

        let result = await makeService(context: context)
            .compareWithPrevious(workout: current)
        #expect(result.first?.previousPerformance?.sets.first?.weight == 20)
    }

    @Test
    func routineRenameKeepsComparisonContinuity() async throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Biceps Curls")
        let routine = Routine(name: "Old Pull")
        context.insert(exercise)
        context.insert(routine)

        let previous = WorkoutSession(routine: routine)
        previous.startTime = Date(timeIntervalSince1970: 1_000)
        previous.endTime = Date(timeIntervalSince1970: 1_100)
        context.insert(previous)
        addPerformance(exercise, weight: 20, reps: 5, order: 0, to: previous, context: context)

        routine.name = "Pull"
        let current = WorkoutSession(routine: routine)
        current.startTime = Date(timeIntervalSince1970: 2_000)
        current.endTime = Date(timeIntervalSince1970: 2_100)
        context.insert(current)
        addPerformance(exercise, weight: 21, reps: 5, order: 0, to: current, context: context)
        try context.save()

        let result = await makeService(context: context)
            .compareWithPrevious(workout: current)
        #expect(result.first?.previousPerformance?.sets.first?.weight == 20)
    }

    @Test
    func ambiguousLegacyNameDoesNotChooseAnEquipmentVariant() async throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let barbell = Exercise(name: "Biceps Curls", equipmentType: .barbell)
        let dumbbell = Exercise(name: "Biceps Curls", equipmentType: .dumbbell)
        let routine = Routine(name: "Pull")
        context.insert(barbell)
        context.insert(dumbbell)
        context.insert(routine)

        let previous = WorkoutSession(routine: routine)
        previous.startTime = Date(timeIntervalSince1970: 1_000)
        previous.endTime = Date(timeIntervalSince1970: 1_100)
        context.insert(previous)
        let legacyExercise = WorkoutExercise(
            exerciseName: barbell.name,
            muscleGroups: barbell.muscleGroups,
            order: 0
        )
        legacyExercise.workoutSession = previous
        context.insert(legacyExercise)
        let legacySet = WorkoutSet(
            plannedReps: 5,
            actualReps: 5,
            plannedWeight: 20,
            actualWeight: 20,
            restTime: 60,
            order: 0
        )
        legacySet.isCompleted = true
        legacySet.workoutExercise = legacyExercise
        context.insert(legacySet)

        let current = WorkoutSession(routine: routine)
        current.startTime = Date(timeIntervalSince1970: 2_000)
        current.endTime = Date(timeIntervalSince1970: 2_100)
        context.insert(current)
        addPerformance(barbell, weight: 21, reps: 5, order: 0, to: current, context: context)
        try context.save()

        let result = await makeService(context: context)
            .compareWithPrevious(workout: current)
        #expect(result.first?.previousPerformance == nil)
    }

    @Test
    func missingRoutineIdentityDoesNotFallBackToDuplicateRoutineName() async throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Biceps Curls")
        let routine = Routine(name: "Pull")
        context.insert(exercise)
        context.insert(routine)

        let previous = WorkoutSession(routine: routine)
        previous.routine = nil
        previous.startTime = Date(timeIntervalSince1970: 1_000)
        previous.endTime = Date(timeIntervalSince1970: 1_100)
        context.insert(previous)
        addPerformance(exercise, weight: 13, reps: 12, order: 0, to: previous, context: context)

        let current = WorkoutSession(routine: routine)
        current.routine = nil
        current.startTime = Date(timeIntervalSince1970: 2_000)
        current.endTime = Date(timeIntervalSince1970: 2_100)
        context.insert(current)
        addPerformance(exercise, weight: 20, reps: 5, order: 0, to: current, context: context)
        try context.save()

        let result = await makeService(context: context)
            .compareWithPrevious(workout: current)
        #expect(result.first?.previousPerformance == nil)
    }
}
