//
//  PersonalRecordServiceTests.swift
//  GymStreakTests
//
//  Regression coverage for attributing an exercise-wide PR to one workout occurrence.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct PersonalRecordServiceTests {

    @Test
    func repeatedExerciseAttributesPRToOnlyTheWinningOccurrence() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Biceps Curls")
        let routine = Routine(name: "Pull")
        context.insert(exercise)
        context.insert(routine)

        let previous = WorkoutSession(routine: routine)
        previous.startTime = Date(timeIntervalSince1970: 1_000)
        previous.endTime = Date(timeIntervalSince1970: 1_600)
        context.insert(previous)
        addExercise(
            exercise,
            to: previous,
            order: 0,
            weight: 12,
            reps: 10,
            context: context
        )

        let current = WorkoutSession(routine: routine)
        current.startTime = Date(timeIntervalSince1970: 2_000)
        current.endTime = Date(timeIntervalSince1970: 2_600)
        context.insert(current)
        let heavy = addExercise(
            exercise,
            to: current,
            order: 0,
            weight: 20,
            reps: 5,
            context: context
        )
        let highRep = addExercise(
            exercise,
            to: current,
            order: 1,
            weight: 13,
            reps: 12,
            context: context
        )
        try context.save()

        let result = PersonalRecordService.computePRs(sessions: [previous, current])
        let details = try #require(result.prDetailsBySession[current.id])

        #expect(result.prCountBySession[current.id] == 1)
        #expect(details[heavy.id] != nil)
        #expect(details[highRep.id] == nil)
    }

    @discardableResult
    private func addExercise(
        _ exercise: Exercise,
        to session: WorkoutSession,
        order: Int,
        weight: Double,
        reps: Int,
        context: ModelContext
    ) -> WorkoutExercise {
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
        return workoutExercise
    }
}
