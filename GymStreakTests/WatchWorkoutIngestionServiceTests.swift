//
//  WatchWorkoutIngestionServiceTests.swift
//  GymStreakTests
//
//  Verifies that the routine-slot UUID already carried by the Watch payload
//  survives materialization into workout history.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct WatchWorkoutIngestionServiceTests {

    @Test
    func ingestPreservesRoutineExerciseIdentity() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let exercise = Exercise(name: "Biceps Curls")
        let routine = Routine(name: "Pull")
        let routineExercise = RoutineExercise(exercise: exercise, order: 0)
        routineExercise.routine = routine
        context.insert(exercise)
        context.insert(routineExercise)
        routineRepository.insert(routine)
        try routineRepository.save()

        let workoutId = UUID()
        let incoming = IncomingWatchWorkout(
            id: workoutId,
            routineId: routine.id,
            routineName: routine.name,
            startTime: Date(timeIntervalSince1970: 1_000),
            endTime: Date(timeIntervalSince1970: 1_600),
            exercises: [
                IncomingWatchExercise(
                    id: routineExercise.id,
                    name: exercise.name,
                    muscleGroup: exercise.primaryMuscleGroup,
                    sets: [
                        IncomingWatchSet(
                            id: UUID(),
                            plannedReps: 5,
                            actualReps: 5,
                            plannedWeight: 20,
                            actualWeight: 20,
                            restTime: 60,
                            isCompleted: true,
                            completedAt: Date(timeIntervalSince1970: 1_100),
                            order: 0
                        )
                    ],
                    order: 0,
                    supersetId: nil,
                    supersetOrder: 0,
                    targetRepMin: 4,
                    targetRepMax: 6,
                    exerciseId: exercise.id,
                    loadBehaviorRaw: ExerciseLoadBehavior.resistance.rawValue,
                    plannedExerciseId: nil,
                    plannedExerciseName: nil
                )
            ],
            shouldUpdateTemplate: false,
            healthKitWorkoutId: nil
        )

        let result = WatchWorkoutIngestionService(
            routineRepository: routineRepository,
            workoutSessionRepository: sessionRepository
        ).ingest(incoming)
        let stored = try #require(sessionRepository.findSession(id: workoutId, healthKitWorkoutId: nil))

        #expect(result.shouldAcknowledge)
        #expect(stored.workoutExercisesList.first?.routineExerciseId == routineExercise.id)
    }
}
