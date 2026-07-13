//
//  ExerciseProgressServiceTests.swift
//  GymStreakTests
import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct ExerciseProgressServiceTests {

    @Test
    func repeatedExerciseComparesEachRoutineOccurrenceWithItsPreviousCounterpart() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Biceps Curls")
        let routine = Routine(name: "Pull")
        context.insert(exercise)
        context.insert(routine)

        let previous = makeCompletedSession(
            routine: routine,
            startTime: Date(timeIntervalSince1970: 1_000),
            performances: [
                (order: 1, weight: 13, reps: 12, routineExerciseId: nil),
                (order: 0, weight: 20, reps: 5, routineExerciseId: nil)
            ],
            exercise: exercise,
            context: context
        )
        let current = makeCompletedSession(
            routine: routine,
            startTime: Date(timeIntervalSince1970: 2_000),
            performances: [
                (order: 0, weight: 20, reps: 5, routineExerciseId: nil),
                (order: 1, weight: 13, reps: 12, routineExerciseId: nil)
            ],
            exercise: exercise,
            context: context
        )
        try context.save()

        let results = ExerciseProgressService(modelContext: context)
            .compareWithPrevious(workout: current)

        #expect(previous.workoutExercisesList.count == 2)
        #expect(results.count == 2)
        #expect(results[0].previousPerformance?.sets.first?.weight == 20)
        #expect(results[1].previousPerformance?.sets.first?.weight == 13)
    }

    @Test
    func routineSlotIdentitySurvivesExerciseReordering() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Biceps Curls")
        let routine = Routine(name: "Pull")
        let heavySlotId = UUID()
        let highRepSlotId = UUID()
        context.insert(exercise)
        context.insert(routine)

        _ = makeCompletedSession(
            routine: routine,
            startTime: Date(timeIntervalSince1970: 1_000),
            performances: [
                (order: 0, weight: 20, reps: 5, routineExerciseId: heavySlotId),
                (order: 1, weight: 13, reps: 12, routineExerciseId: highRepSlotId)
            ],
            exercise: exercise,
            context: context
        )
        let current = makeCompletedSession(
            routine: routine,
            startTime: Date(timeIntervalSince1970: 2_000),
            performances: [
                (order: 0, weight: 13, reps: 12, routineExerciseId: highRepSlotId),
                (order: 1, weight: 20, reps: 5, routineExerciseId: heavySlotId)
            ],
            exercise: exercise,
            context: context
        )
        try context.save()

        let results = ExerciseProgressService(modelContext: context)
            .compareWithPrevious(workout: current)

        #expect(results[0].previousPerformance?.sets.first?.weight == 13)
        #expect(results[1].previousPerformance?.sets.first?.weight == 20)
    }

    @Test
    func sameNameEquipmentVariantsRemainSeparate() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let barbell = Exercise(name: "Biceps Curls", equipmentType: .barbell)
        let dumbbell = Exercise(name: "Biceps Curls", equipmentType: .dumbbell)
        let routine = Routine(name: "Pull")
        context.insert(barbell)
        context.insert(dumbbell)
        context.insert(routine)

        let previous = WorkoutSession(routine: routine)
        previous.startTime = Date(timeIntervalSince1970: 1_000)
        previous.endTime = Date(timeIntervalSince1970: 1_600)
        context.insert(previous)
        addPerformance(barbell, weight: 30, reps: 6, order: 0, to: previous, context: context)
        addPerformance(dumbbell, weight: 13, reps: 12, order: 1, to: previous, context: context)

        let current = WorkoutSession(routine: routine)
        current.startTime = Date(timeIntervalSince1970: 2_000)
        current.endTime = Date(timeIntervalSince1970: 2_600)
        context.insert(current)
        addPerformance(barbell, weight: 32, reps: 6, order: 0, to: current, context: context)
        addPerformance(dumbbell, weight: 14, reps: 12, order: 1, to: current, context: context)
        try context.save()

        let results = ExerciseProgressService(modelContext: context)
            .compareWithPrevious(workout: current)

        #expect(results[0].previousPerformance?.sets.first?.weight == 30)
        #expect(results[1].previousPerformance?.sets.first?.weight == 13)
    }

    private func makeCompletedSession(
        routine: Routine,
        startTime: Date,
        performances: [(order: Int, weight: Double, reps: Int, routineExerciseId: UUID?)],
        exercise: Exercise,
        context: ModelContext
    ) -> WorkoutSession {
        let session = WorkoutSession(routine: routine)
        session.startTime = startTime
        session.endTime = startTime.addingTimeInterval(600)
        context.insert(session)

        for performance in performances {
            let workoutExercise = WorkoutExercise(
                exerciseName: exercise.name,
                muscleGroups: exercise.muscleGroups,
                order: performance.order,
                exerciseId: exercise.id
            )
            workoutExercise.routineExerciseId = performance.routineExerciseId
            workoutExercise.workoutSession = session
            context.insert(workoutExercise)

            let set = WorkoutSet(
                plannedReps: performance.reps,
                actualReps: performance.reps,
                plannedWeight: performance.weight,
                actualWeight: performance.weight,
                restTime: 60,
                order: 0
            )
            set.isCompleted = true
            set.workoutExercise = workoutExercise
            context.insert(set)
        }

        return session
    }

    func addPerformance(
        _ exercise: Exercise,
        weight: Double,
        reps: Int,
        order: Int,
        to session: WorkoutSession,
        context: ModelContext
    ) {
        let workoutExercise = WorkoutExercise(
            exerciseName: exercise.name,
            muscleGroups: exercise.muscleGroups,
            order: order,
            exerciseId: exercise.id
        )
        workoutExercise.workoutSession = session
        context.insert(workoutExercise)

        let set = WorkoutSet(
            plannedReps: reps,
            actualReps: reps,
            plannedWeight: weight,
            actualWeight: weight,
            restTime: 60,
            order: 0
        )
        set.isCompleted = true
        set.workoutExercise = workoutExercise
        context.insert(set)
    }
}
