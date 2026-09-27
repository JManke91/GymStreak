//
//  RoutineDraftEditingTests.swift
//  GymStreakTests
//
//  The AI routine draft (docs/ai-coach-routine-drafting.md), ticket 03: the draft is a
//  starting point the person edits in place — rename, reorder, remove, reopen an
//  exercise's sets — before Create.
//
//  What carries this ticket: `order` is renumbered from the list the sheet showed, not
//  carried over from the draft; an edit reaches the store exactly as the set editor
//  returned it; and none of it costs an allowance unit or calls the model again.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct RoutineDraftEditingTests {

    /// A finished three-exercise draft, ready for review.
    private func reviewedHarness() async -> RoutineDraftHarness {
        let harness = RoutineDraftHarness.make(libraryNames: ["Bench Press", "Row", "Squat"])
        harness.drafting.snapshots = [routineDraftSnapshot(name: "Push Day", [
            routineDraftEntry("Bench Press", sets: 3, reps: 8, weight: 60),
            routineDraftEntry("Row", sets: 3, reps: 10, weight: 50),
            routineDraftEntry("Squat", sets: 4, reps: 5, weight: 100),
        ])]
        harness.viewModel.onAppear(weightUnit: .kilograms)
        harness.viewModel.descriptionText = "Push day: bench press 3x8 at 60 kg, row 3x10 at 50 kg, squat 4x5 at 100 kg"
        harness.viewModel.submit()
        await harness.settle()
        return harness
    }

    // MARK: - Rename

    @Test("A renamed draft is created under the new name")
    func renameReachesCreate() async {
        let harness = await reviewedHarness()

        harness.viewModel.routineName = "  Upper A  "
        harness.viewModel.createRoutine()

        #expect(harness.routines.createdNames == ["Upper A"])
    }

    @Test("Editing a row does not put the drafted name back")
    func renameSurvivesOtherEdits() async throws {
        let harness = await reviewedHarness()

        harness.viewModel.routineName = "Upper A"
        let row = try #require(harness.viewModel.rows.last)
        harness.viewModel.removeRow(row.id)

        #expect(harness.viewModel.routineName == "Upper A")
    }

    // MARK: - Reorder and remove

    @Test("Reordering renumbers order so the saved routine matches the sheet")
    func reorderThenSaveRenumbersOrder() async throws {
        let harness = await reviewedHarness()

        let squat = try #require(harness.viewModel.rows.last)
        #expect(squat.canMoveDown == false)
        harness.viewModel.moveRow(squat.id, by: -1)
        harness.viewModel.moveRow(squat.id, by: -1)
        // Clamped at the top, not wrapped or dropped.
        harness.viewModel.moveRow(squat.id, by: -1)

        #expect(harness.viewModel.rows.map(\.name) == ["Squat", "Bench Press", "Row"])
        #expect(harness.viewModel.rows.first?.canMoveUp == false)

        harness.viewModel.createRoutine()
        let written = try #require(harness.routines.createdExercises.first)
        #expect(written.map(\.exercise.name) == ["Squat", "Bench Press", "Row"])
        #expect(written.map(\.order) == [0, 1, 2])
    }

    @Test("Removing a resolved exercise leaves it out and closes the gap in order")
    func removeThenSave() async throws {
        let harness = await reviewedHarness()

        let row = try #require(harness.viewModel.rows.first { $0.name == "Row" })
        harness.viewModel.removeRow(row.id)

        #expect(harness.viewModel.rows.map(\.name) == ["Bench Press", "Squat"])

        harness.viewModel.createRoutine()
        let written = try #require(harness.routines.createdExercises.first)
        #expect(written.map(\.exercise.name) == ["Bench Press", "Squat"])
        #expect(written.map(\.order) == [0, 1])
    }

    @Test("Removing every exercise leaves nothing to create")
    func removingEverythingDisablesCreate() async {
        let harness = await reviewedHarness()

        for row in harness.viewModel.rows { harness.viewModel.removeRow(row.id) }

        #expect(harness.viewModel.canCreate == false)
    }

    // MARK: - Editing sets

    @Test("The set editor opens on the drafted sets, reps and weight")
    func configurationIsSeededWithTheDraftedScheme() async throws {
        let harness = await reviewedHarness()

        let squat = try #require(harness.viewModel.rows.last)
        let pending = try #require(harness.viewModel.configuration(for: squat.id))

        #expect(pending.exercise.name == "Squat")
        #expect(pending.sets.count == 4)
        #expect(pending.sets.allSatisfy { $0.reps == 5 && $0.weight == 100 })
    }

    @Test("Saved edits return to the draft, show in the row and reach Create")
    func editedSetsReachCreate() async throws {
        let harness = await reviewedHarness()

        let bench = try #require(harness.viewModel.rows.first)
        harness.viewModel.updateConfiguration(
            bench.id,
            sets: [
                ExerciseSet(reps: 5, weight: 80, restTime: 120, order: 0),
                ExerciseSet(reps: 5, weight: 80, restTime: 120, order: 1),
            ],
            alternatives: [],
            targetRepMin: 4,
            targetRepMax: 6
        )

        let edited = try #require(harness.viewModel.rows.first)
        #expect(edited.summary.contains("2"))
        // Reopening shows the edit, not the drafted scheme.
        #expect(harness.viewModel.configuration(for: bench.id)?.sets.count == 2)

        // An edited row still follows a later move.
        harness.viewModel.moveRow(bench.id, by: 1)
        harness.viewModel.createRoutine()

        let written = try #require(harness.routines.createdExercises.first)
        #expect(written.map(\.exercise.name) == ["Row", "Bench Press", "Squat"])
        #expect(written.map(\.order) == [0, 1, 2])
        let writtenBench = written[1]
        #expect(writtenBench.sets.count == 2)
        #expect(writtenBench.sets.allSatisfy { $0.reps == 5 && $0.weight == 80 })
        #expect(writtenBench.targetRepMin == 4)
        #expect(writtenBench.targetRepMax == 6)
        // Untouched rows keep their drafted scheme.
        #expect(written[2].sets.count == 4)
    }

    @Test("An unresolved row has nothing to configure")
    func unresolvedRowHasNoConfiguration() async throws {
        let harness = RoutineDraftHarness.make(libraryNames: ["Bench Press"])
        harness.drafting.snapshots = [routineDraftSnapshot([routineDraftEntry("Flurbelblatz")])]
        harness.viewModel.onAppear(weightUnit: .kilograms)
        harness.viewModel.descriptionText = "Push day: Flurbelblatz"
        harness.viewModel.submit()
        await harness.settle()

        let row = try #require(harness.viewModel.rows.first)
        #expect(harness.viewModel.configuration(for: row.id) == nil)
    }

    // MARK: - Cost

    @Test("Editing consumes no allowance unit and never calls the model")
    func editingIsFree() async throws {
        let harness = await reviewedHarness()
        #expect(harness.allowance.consumeCount == 1)
        #expect(harness.drafting.requestedDescriptions.count == 1)

        let rows = harness.viewModel.rows
        harness.viewModel.routineName = "Upper A"
        harness.viewModel.moveRow(rows[2].id, by: -2)
        harness.viewModel.updateConfiguration(
            rows[0].id,
            sets: [ExerciseSet(reps: 3, weight: 90, restTime: 60, order: 0)],
            alternatives: [],
            targetRepMin: nil,
            targetRepMax: nil
        )
        harness.viewModel.removeRow(rows[1].id)
        harness.viewModel.createRoutine()

        #expect(harness.allowance.consumeCount == 1)
        #expect(harness.allowance.refundCount == 0)
        #expect(harness.drafting.requestedDescriptions.count == 1)
    }

    // MARK: - Into SwiftData

    @Test("Edits round-trip through createRoutine into SwiftData")
    func editedDraftPersists() async throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let library = ["Bench Press", "Squat"].map { name in
            let exercise = Exercise(name: name)
            context.insert(exercise)
            return exercise
        }
        let routines = RoutinesViewModel(
            routineRepository: SwiftDataRoutineRepository(modelContext: context),
            workoutSessionRepository: SwiftDataWorkoutSessionRepository(modelContext: context),
            watchSync: MockWatchSyncServicing(),
            proEntitlements: StubProEntitlements(state: .free),
            paywalls: RecordingPaywallPresenter(),
            isGatingEnabled: false
        )
        let availability = StubAICoachAvailability(state: .available)
        let paywalls = RecordingPaywallPresenter()
        let drafting = FakeRoutineDrafting()
        drafting.snapshots = [routineDraftSnapshot(name: "Legs", [
            routineDraftEntry("Bench Press", sets: 4, reps: 8, weight: 60),
            routineDraftEntry("Squat", sets: 3, reps: 5, weight: 100),
        ])]
        let viewModel = RoutineDraftViewModel(
            allowanceGate: AICoachAllowanceGate(
                surface: .coachChat,
                entitlements: StubProEntitlements(state: .free),
                paywalls: paywalls,
                allowance: SpyAllowanceStore(),
                availability: availability,
                isGatingEnabled: true
            ),
            drafting: drafting,
            exerciseRepository: FakeExerciseRepository(exercises: library),
            routines: routines,
            paywalls: paywalls,
            availability: availability
        )
        viewModel.onAppear(weightUnit: .kilograms)
        viewModel.descriptionText = "Legs: bench press and squat"
        viewModel.submit()
        for _ in 0..<500 where viewModel.isDrafting { await Task.yield() }

        let bench = try #require(viewModel.rows.first)
        let squat = try #require(viewModel.rows.last)
        viewModel.routineName = "Lower A"
        // 4 drafted sets → 3.
        viewModel.updateConfiguration(
            bench.id,
            sets: (0..<3).map { ExerciseSet(reps: 8, weight: 60, restTime: 90, order: $0) },
            alternatives: [],
            targetRepMin: nil,
            targetRepMax: nil
        )
        viewModel.moveRow(squat.id, by: -1)
        viewModel.createRoutine()

        let persisted = try context.fetch(FetchDescriptor<Routine>())
        let routine = try #require(persisted.first)
        #expect(persisted.count == 1)
        #expect(routine.name == "Lower A")
        // Sorted the way every read sorts: a to-many relationship's array order is not
        // guaranteed, which is exactly why `order` is stored.
        let exercises = routine.routineExercisesList.sorted { $0.order < $1.order }
        #expect(exercises.map { $0.exercise?.name } == ["Squat", "Bench Press"])
        #expect(exercises.map(\.order) == [0, 1])
        #expect(exercises.last?.setsList.count == 3)
        #expect(exercises.first?.setsList.count == 3)
    }
}
