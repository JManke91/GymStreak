//
//  RoutinesViewModelTests.swift
//  GymStreakTests
//
//  RoutinesViewModel wired with real in-memory repositories and a recording
//  WatchSyncServicing double. Covers the createRoutine(name:pendingExercises:)
//  transaction (routine + exercise + sets + alternatives graph) and
//  deleteRoutine, both against the real SwiftData persistence layer.
//

import Testing
import SwiftData
import Foundation
@testable import GymStreak

// Serialized: see SwiftDataRoutineRepositoryTests for why in-memory ModelContainer
// creation must not run concurrently within this process.
@Suite(.serialized)
@MainActor
struct RoutinesViewModelTests {

    private func makeViewModel() -> (
        viewModel: RoutinesViewModel,
        watchSync: MockWatchSyncServicing,
        context: ModelContext
    ) {
        let container = InMemoryModelContainer.make()
        let context = ModelContext(container)
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let workoutSessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let watchSync = MockWatchSyncServicing()
        let viewModel = RoutinesViewModel(
            routineRepository: routineRepository,
            workoutSessionRepository: workoutSessionRepository,
            watchSync: watchSync
        )
        return (viewModel, watchSync, context)
    }

    @Test
    func createRoutinePersistsExerciseSetsAndAlternatives() throws {
        let (viewModel, _, context) = makeViewModel()

        let exercise = Exercise(name: "Bench Press")
        let alternativeExercise = Exercise(name: "Incline Dumbbell Press")
        let sets = [ExerciseSet(reps: 8, weight: 60, restTime: 90, order: 0)]
        let alternative = PendingAlternative(
            exercise: alternativeExercise,
            sets: [ExerciseSet(reps: 10, weight: 0, restTime: 90, order: 0)]
        )
        let pending = PendingRoutineExercise(exercise: exercise, sets: sets, order: 0, alternatives: [alternative])

        viewModel.createRoutine(name: "Push Day", pendingExercises: [pending])

        #expect(viewModel.routines.count == 1)
        let routine = try #require(viewModel.routines.first)
        #expect(routine.name == "Push Day")

        let routineExercise = try #require(routine.routineExercisesList.first)
        #expect(routineExercise.exercise?.name == "Bench Press")
        #expect(routineExercise.setsList.count == 1)
        #expect(routineExercise.setsList.first?.reps == 8)
        #expect(routineExercise.alternativesList.count == 1)
        #expect(routineExercise.alternativesList.first?.exercise?.name == "Incline Dumbbell Press")
        #expect(routineExercise.alternativesList.first?.setsList.first?.reps == 10)

        // Confirm the graph round-trips through the persistence layer, not just
        // the in-memory @Published state.
        let persistedRoutines = try context.fetch(FetchDescriptor<Routine>())
        let persistedExercises = try context.fetch(FetchDescriptor<RoutineExercise>())
        let persistedAlternatives = try context.fetch(FetchDescriptor<RoutineExerciseAlternative>())
        #expect(persistedRoutines.count == 1)
        #expect(persistedExercises.count == 1)
        #expect(persistedAlternatives.count == 1)
    }

    @Test
    func createRoutineIgnoresBlankName() {
        let (viewModel, _, _) = makeViewModel()
        viewModel.createRoutine(name: "   ", pendingExercises: [])
        #expect(viewModel.routines.isEmpty)
    }

    @Test
    func deleteRoutineRemovesItFromStoreAndPublishedList() throws {
        let (viewModel, _, context) = makeViewModel()
        viewModel.addRoutine(name: "Leg Day")
        let routine = try #require(viewModel.routines.first)

        viewModel.deleteRoutine(routine)

        #expect(viewModel.routines.isEmpty)
        let persisted = try context.fetch(FetchDescriptor<Routine>())
        #expect(persisted.isEmpty)
    }

    @Test
    func fetchRoutinesSyncsCurrentListToWatch() {
        let (viewModel, watchSync, _) = makeViewModel()
        viewModel.addRoutine(name: "Pull Day")
        #expect(watchSync.syncRoutinesCalls.last?.map(\.name) == ["Pull Day"])
    }
}
