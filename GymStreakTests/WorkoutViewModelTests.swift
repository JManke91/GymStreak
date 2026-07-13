//
//  WorkoutViewModelTests.swift
//  GymStreakTests
//
//  Covers workout occurrence identity across iPhone creation and swaps.
//

import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct WorkoutViewModelTests {

    @Test
    func routineWorkoutSnapshotsSlotWhileAdHocExerciseDoesNot() {
        let exercise = Exercise(name: "Biceps Curls")
        let routineExercise = RoutineExercise(exercise: exercise, order: 0)

        let planned = WorkoutExercise(from: routineExercise, order: 0)
        let adHoc = WorkoutExercise(
            exerciseName: exercise.name,
            muscleGroups: exercise.muscleGroups,
            order: 0,
            exerciseId: exercise.id
        )

        #expect(planned.routineExerciseId == routineExercise.id)
        #expect(adHoc.routineExerciseId == nil)
    }

    @Test
    func swapAndRevertPreserveSlotAndSnapshotPerformedLoadBehavior() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let primary = Exercise(name: "Chin Up", loadBehavior: .resistance)
        let alternative = Exercise(
            name: "Assisted Chin Up",
            loadBehavior: .counterweightAssistance
        )
        let routine = Routine(name: "Pull")
        let slot = RoutineExercise(exercise: primary, order: 0)
        slot.routine = routine
        routine.routineExercises = [slot]

        let primarySet = ExerciseSet(reps: 6, weight: 0, restTime: 60)
        primarySet.routineExercise = slot
        slot.sets = [primarySet]

        let alternativeUse = RoutineExerciseAlternative(exercise: alternative, order: 0)
        alternativeUse.routineExercise = slot
        let alternativeSet = AlternativeExerciseSet(reps: 8, weight: 20, restTime: 60)
        alternativeSet.alternative = alternativeUse
        alternativeUse.sets = [alternativeSet]
        slot.alternatives = [alternativeUse]

        context.insert(primary)
        context.insert(alternative)
        context.insert(slot)
        context.insert(primarySet)
        context.insert(alternativeUse)
        context.insert(alternativeSet)
        routineRepository.insert(routine)

        let session = WorkoutSession(routine: routine)
        let workoutExercise = WorkoutExercise(from: slot, order: 0)
        workoutExercise.workoutSession = session
        session.workoutExercises = [workoutExercise]
        sessionRepository.insert(session)
        try sessionRepository.save()

        let viewModel = WorkoutViewModel(
            workoutSessionRepository: sessionRepository,
            routineRepository: routineRepository,
            healthKitManager: MockHealthKitWorkoutServicing(),
            watchSync: MockWatchSyncServicing()
        )
        viewModel.currentSession = session

        let alternativeTarget = try #require(
            viewModel.swapTargets(for: workoutExercise).first { $0.exercise.id == alternative.id }
        )
        viewModel.swapExercise(workoutExercise, to: alternativeTarget)

        #expect(workoutExercise.routineExerciseId == slot.id)
        #expect(workoutExercise.exerciseId == alternative.id)
        #expect(workoutExercise.loadBehavior == .counterweightAssistance)

        let revertTarget = try #require(
            viewModel.swapTargets(for: workoutExercise).first { $0.isOriginal }
        )
        viewModel.swapExercise(workoutExercise, to: revertTarget)

        #expect(workoutExercise.routineExerciseId == slot.id)
        #expect(workoutExercise.exerciseId == primary.id)
        #expect(workoutExercise.loadBehavior == .resistance)
    }
}
