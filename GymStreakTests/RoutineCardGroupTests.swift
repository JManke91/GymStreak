//
//  RoutineCardGroupTests.swift
//  GymStreakTests
//
//  The Routines tab's per-program grouping (docs/routine-programs.md, ticket 05):
//  membership comes from a catalog lookup of `seedKey`, the hero is excluded, and
//  the own-routines label switches to "Your routines" once a program is installed.
//

import Testing
import SwiftData
import Foundation
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct RoutineCardGroupTests {

    private let fullBodyA = "seed.program.full_body.a"
    private let fullBodyB = "seed.program.full_body.b"
    private let exampleKey = "seed.routine.full_body_starter"

    private func makeViewModel() -> (viewModel: RoutinesViewModel, context: ModelContext) {
        let container = InMemoryModelContainer.make()
        let context = ModelContext(container)
        let viewModel = RoutinesViewModel(
            routineRepository: SwiftDataRoutineRepository(modelContext: context),
            workoutSessionRepository: SwiftDataWorkoutSessionRepository(modelContext: context),
            watchSync: MockWatchSyncServicing(),
            proEntitlements: StubProEntitlements(state: .free),
            paywalls: RecordingPaywallPresenter(),
            isGatingEnabled: false
        )
        return (viewModel, context)
    }

    private func insertRoutine(_ name: String, seedKey: String = "", in context: ModelContext) -> Routine {
        let routine = Routine(name: name)
        routine.seedKey = seedKey
        context.insert(routine)
        return routine
    }

    /// Unplanned, the least-recently-trained routine is the hero. Training every
    /// routine but `hero` pins which one that is.
    private func train(_ routines: [Routine], in context: ModelContext) throws {
        for routine in routines {
            let session = WorkoutSession(routine: routine)
            session.startTime = Date(timeIntervalSince1970: 9_000)
            session.endTime = Date(timeIntervalSince1970: 9_500)
            context.insert(session)
        }
        try context.save()
    }

    @Test("Program routines group under their program; own, example and duplicate under Your routines")
    func programRoutinesGroupAndEverythingElseIsOwn() throws {
        let (viewModel, context) = makeViewModel()
        let hero = insertRoutine("Pull Day", in: context)
        let own = insertRoutine("Push Day", in: context)
        let example = insertRoutine("Example", seedKey: exampleKey, in: context)
        let routineA = insertRoutine("Full Body A", seedKey: fullBodyA, in: context)
        let routineB = insertRoutine("Full Body B", seedKey: fullBodyB, in: context)
        try context.save()
        viewModel.fetchRoutines()

        let duplicate = try #require(viewModel.duplicateRoutine(routineA))
        #expect(duplicate.seedKey == "")
        try train([own, example, routineA, routineB, duplicate], in: context)
        viewModel.fetchRoutines()

        #expect(viewModel.heroCard?.id == hero.id)
        #expect(viewModel.heroProgramName == nil)
        #expect(viewModel.cardGroups.map(\.programId) == ["full_body", nil])

        let program = try #require(viewModel.cardGroups.first)
        #expect(program.title == "routine_programs.full_body.name".localized)
        #expect(Set(program.cards.map(\.id)) == [routineA.id, routineB.id])

        let ownGroup = try #require(viewModel.cardGroups.last)
        #expect(ownGroup.title == "routines.own".localized)
        #expect(Set(ownGroup.cards.map(\.id)) == [own.id, example.id, duplicate.id])
    }

    @Test("A partly installed program still gets its section")
    func partiallyInstalledProgramStillGroups() throws {
        let (viewModel, context) = makeViewModel()
        _ = insertRoutine("Pull Day", in: context)
        let routineB = insertRoutine("Full Body B", seedKey: fullBodyB, in: context)
        try train([routineB], in: context)
        viewModel.fetchRoutines()

        #expect(viewModel.cardGroups.map(\.programId) == ["full_body"])
        #expect(viewModel.cardGroups.first?.cards.map(\.id) == [routineB.id])
    }

    @Test("A program hero names its program and leaves the rest of the program in the section")
    func heroShowsItsProgramName() throws {
        let (viewModel, context) = makeViewModel()
        let routineA = insertRoutine("Full Body A", seedKey: fullBodyA, in: context)
        let routineB = insertRoutine("Full Body B", seedKey: fullBodyB, in: context)
        let own = insertRoutine("Push Day", in: context)
        try train([routineB, own], in: context)
        viewModel.fetchRoutines()

        #expect(viewModel.heroCard?.id == routineA.id)
        #expect(viewModel.heroProgramName == "routine_programs.full_body.name".localized)
        #expect(viewModel.cardGroups.first?.cards.map(\.id) == [routineB.id])
        // The hero alone makes a program installed, so the label already switched.
        #expect(viewModel.cardGroups.last?.title == "routines.own".localized)
    }

    @Test("Without a program the list keeps its single All routines section")
    func noProgramKeepsAllRoutines() throws {
        let (viewModel, context) = makeViewModel()
        _ = insertRoutine("Pull Day", in: context)
        let own = insertRoutine("Push Day", in: context)
        let example = insertRoutine("Example", seedKey: exampleKey, in: context)
        try train([own, example], in: context)
        viewModel.fetchRoutines()

        #expect(viewModel.cardGroups.map(\.programId) == [nil])
        #expect(viewModel.cardGroups.first?.title == "routines.all".localized)
        #expect(viewModel.cardGroups.first?.cards.count == 2)
    }

    /// The membership lookup is built with `Dictionary(uniqueKeysWithValues:)`, which
    /// traps on a duplicate — a copy-pasted seedKey in a new program must fail here, not at launch.
    @Test("Every program routine seedKey is unique across the catalog")
    func programRoutineSeedKeysAreUnique() {
        let keys = RoutineProgramCatalog.programs.flatMap { $0.routines.map(\.seedKey) }
        #expect(Set(keys).count == keys.count)
        #expect(RoutineProgramCatalog.program(forRoutineSeedKey: fullBodyA)?.id == "full_body")
        #expect(RoutineProgramCatalog.program(forRoutineSeedKey: "") == nil)
    }
}
