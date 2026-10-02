//
//  RoutineDraftCreateExerciseTests.swift
//  GymStreakTests
//
//  The AI routine draft (docs/ai-coach-routine-drafting.md §6a): a name the library could
//  not place can be **created** from the picker. Saving the add-exercise screen writes the
//  exercise and resolves the tapped row to it through the ordinary resolve path — so the
//  drafted figures survive, other rows are untouched and no allowance unit is spent. The
//  exercise is the person's own write, so it outlives a discarded draft.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

private final class NoopCatalogSync: ExerciseCatalogSyncRequesting {
    func requestCatalogSync() {}
}

@Suite(.serialized)
@MainActor
struct RoutineDraftCreateExerciseTests {

    @Test("A created exercise resolves only the tapped row, keeping its figures, for no unit")
    func createdExerciseResolvesOnlyTheTappedRow() async throws {
        let harness = RoutineDraftHarness.make(libraryNames: ["Bench Press"])
        harness.drafting.snapshots = [routineDraftSnapshot([
            routineDraftEntry("Nordic Curls", sets: 3, reps: 5, weight: 0),
            routineDraftEntry("Bench Press", sets: 3, reps: 8, weight: 60),
            routineDraftEntry("Nordic Curls", sets: 4, reps: 6, weight: 0),
        ])]
        harness.viewModel.onAppear(weightUnit: .kilograms)
        harness.viewModel.descriptionText = "Nordic Curls 3x5, bench press 3x8 at 60 kg, Nordic Curls 4x6"
        harness.viewModel.submit()
        await harness.settle()
        let spentByTheDraft = harness.allowance.consumeCount
        let modelCalls = harness.drafting.turnCount

        let tapped = try #require(harness.viewModel.rows.first)
        #expect(tapped.isResolved == false)
        // What the add-exercise screen does on save: insert into the library.
        let created = Exercise(name: "Nordic Curls", muscleGroups: ["Hamstrings"])
        harness.exercises.insert(created)
        harness.viewModel.resolveRow(tapped.id, to: created)

        #expect(harness.viewModel.rows.map(\.isResolved) == [true, true, false])
        #expect(harness.viewModel.rows.map(\.id).first == tapped.id)

        harness.viewModel.createRoutine()
        let written = try #require(harness.routines.createdExercises.first)
        #expect(written.map(\.exercise.id) == [created.id, written[1].exercise.id])
        #expect(written.map(\.exercise.name) == ["Nordic Curls", "Bench Press"])
        #expect(written[0].sets.count == 3)
        #expect(written[0].sets.allSatisfy { $0.reps == 5 })
        #expect(harness.allowance.consumeCount == spentByTheDraft)
        #expect(harness.drafting.turnCount == modelCalls)
    }

    @Test("Round trip: the created exercise lands in the saved routine at the row's position")
    func createdExerciseRoundTripsThroughCreateRoutine() async throws {
        let store = try await Store.make(drafting: [
            routineDraftEntry("Bench Press", sets: 3, reps: 8, weight: 60),
            routineDraftEntry("Nordic Curls", sets: 3, reps: 5, weight: 0),
        ])
        let row = try #require(store.draft.rows.last)
        let created = try #require(store.library.addExercise(name: "Nordic Curls", muscleGroups: ["Hamstrings"]))
        store.draft.resolveRow(row.id, to: created)
        store.draft.createRoutine()

        let routine = try #require(try store.context.fetch(FetchDescriptor<Routine>()).first)
        let entries = routine.routineExercisesList.sorted { $0.order < $1.order }
        #expect(entries.map { $0.exercise?.name } == ["Bench Press", "Nordic Curls"])
        #expect(entries.last?.exercise?.id == created.id)
        #expect(entries.last?.setsList.count == 3)
        #expect(entries.last?.setsList.allSatisfy { $0.reps == 5 } == true)
    }

    @Test("Discard keeps the created exercise in the library and writes no routine")
    func discardKeepsTheCreatedExercise() async throws {
        let store = try await Store.make(drafting: [
            routineDraftEntry("Bench Press", sets: 3, reps: 8, weight: 60),
            routineDraftEntry("Nordic Curls", sets: 3, reps: 5, weight: 0),
        ])
        let row = try #require(store.draft.rows.last)
        let created = try #require(store.library.addExercise(name: "Nordic Curls", muscleGroups: ["Hamstrings"]))
        store.draft.resolveRow(row.id, to: created)
        store.draft.discard()

        #expect(try store.context.fetch(FetchDescriptor<Routine>()).isEmpty)
        let names = try store.context.fetch(FetchDescriptor<Exercise>()).map(\.name)
        #expect(names.contains("Nordic Curls"))
    }

    // MARK: - A real store

    /// One in-memory SwiftData context behind the library, the routines and the draft —
    /// as in the app, where all three share the main context.
    @MainActor
    private struct Store {
        let context: ModelContext
        let library: ExercisesViewModel
        let draft: RoutineDraftViewModel

        static func make(drafting entries: [RoutineDraftEntry]) async throws -> Store {
            let context = ModelContext(InMemoryModelContainer.make())
            context.insert(Exercise(name: "Bench Press", muscleGroups: ["Chest"]))
            try context.save()

            let exerciseRepository = SwiftDataExerciseRepository(modelContext: context)
            let routineRepository = SwiftDataRoutineRepository(modelContext: context)
            let routines = RoutinesViewModel(
                routineRepository: routineRepository,
                workoutSessionRepository: SwiftDataWorkoutSessionRepository(modelContext: context),
                watchSync: MockWatchSyncServicing(),
                proEntitlements: StubProEntitlements(state: .free),
                paywalls: RecordingPaywallPresenter(),
                isGatingEnabled: false
            )
            let library = ExercisesViewModel(
                exerciseRepository: exerciseRepository,
                routineRepository: routineRepository,
                catalogSync: NoopCatalogSync()
            )
            let availability = StubAICoachAvailability(state: .available)
            let paywalls = RecordingPaywallPresenter()
            let drafting = FakeRoutineDrafting()
            drafting.snapshots = [routineDraftSnapshot(name: "Legs", entries)]
            let draft = RoutineDraftViewModel(
                allowanceGate: AICoachAllowanceGate(
                    surface: .coachChat,
                    entitlements: StubProEntitlements(state: .free),
                    paywalls: paywalls,
                    allowance: SpyAllowanceStore(),
                    availability: availability,
                    isGatingEnabled: true
                ),
                drafting: drafting,
                exerciseRepository: exerciseRepository,
                routines: routines,
                paywalls: paywalls,
                availability: availability
            )
            draft.onAppear(weightUnit: .kilograms)
            draft.descriptionText = "Legs: bench press 3x8 at 60 kg, Nordic Curls 3x5"
            draft.submit()
            for _ in 0..<500 where draft.isDrafting { await Task.yield() }
            return Store(context: context, library: library, draft: draft)
        }
    }
}
