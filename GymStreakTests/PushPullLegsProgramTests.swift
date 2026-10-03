//
//  PushPullLegsProgramTests.swift
//  GymStreakTests
//
//  Push / Pull / Legs — the first 3-routine program: exact content (deadlift-first
//  Pull, two Push supersets), the every-5-days plan with offsets 0/1/3, gap-filling
//  with offsets relative to the earliest restored routine, the
//  Push · Pull · rest · Legs · rest timeline and the Full Body graduation link
//  (docs/routine-programs.md).
//

import Testing
import SwiftData
import Foundation
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct PushPullLegsProgramTests {

    private static let program = RoutineProgramCatalog.pushPullLegs
    private static let push = "seed.program.ppl.push"
    private static let pull = "seed.program.ppl.pull"
    private static let legs = "seed.program.ppl.legs"

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private static let firstDay = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3))!

    private static func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: firstDay)!
    }

    private func makeContext() throws -> ModelContext {
        let context = ModelContext(InMemoryModelContainer.make())
        let wanted = Set(Self.program.routines.flatMap { $0.exercises.flatMap { [$0.exerciseSeedKey] + $0.alternativeSeedKeys } })
        for row in SeedExerciseCatalog.entries where wanted.contains(row.seedKey) {
            context.insert(row.makeExercise())
        }
        try context.save()
        return context
    }

    private func routines(_ context: ModelContext) throws -> [Routine] {
        try context.fetch(FetchDescriptor<Routine>())
    }

    private func installer(_ context: ModelContext) -> RoutineProgramInstaller {
        RoutineProgramInstaller(modelContext: context, calendar: Self.calendar)
    }

    // MARK: - Content

    @Test
    func everyCatalogProgramReferencesOnlySeedExercises() {
        let catalogKeys = Set(SeedExerciseCatalog.entries.map(\.seedKey))
        let used = RoutineProgramCatalog.programs.flatMap(\.routines).flatMap(\.exercises)
            .flatMap { [$0.exerciseSeedKey] + $0.alternativeSeedKeys }
        #expect(Set(used).isSubset(of: catalogKeys))
    }

    @Test
    func installCreatesThreeRoutinesInTheSignedOffOrder() throws {
        let context = try makeContext()

        #expect(try installer(context).install(Self.program, firstWorkoutDay: nil) == 3)

        let installed = try routines(context)
        #expect(Set(installed.map(\.seedKey)) == [Self.push, Self.pull, Self.legs])

        let pull = try #require(installed.first { $0.seedKey == Self.pull })
        let pullSlots = pull.routineExercisesList.sorted { $0.order < $1.order }
        #expect(pullSlots.map { $0.exercise?.seedKey } == [
            "seed.exercise.deadlift", "seed.exercise.barbell_row", "seed.exercise.lat_pulldown",
            "seed.exercise.seated_cable_row", "seed.exercise.face_pull", "seed.exercise.hammer_curl",
            "seed.exercise.dumbbell_curl",
        ])
        let deadlift = try #require(pullSlots.first)
        #expect(deadlift.setsList.count == 2)
        #expect(deadlift.targetRepMin == 4 && deadlift.targetRepMax == 6)
        #expect(deadlift.setsList.allSatisfy { $0.restTime == 180 && $0.reps == 4 && $0.weight == 0 })
        let row = pullSlots[1]
        #expect(row.setsList.count == 3 && row.targetRepMin == 6 && row.targetRepMax == 10)

        let legs = try #require(installed.first { $0.seedKey == Self.legs })
        let crunch = try #require(legs.routineExercisesList.max { $0.order < $1.order })
        #expect(crunch.exercise?.seedKey == "seed.exercise.cable_crunch")
        #expect(crunch.setsList.count == 3 && crunch.targetRepMin == 10 && crunch.targetRepMax == 15)
    }

    @Test
    func pushHasTwoSupersetsOfPressAndRaise() throws {
        let context = try makeContext()
        try installer(context).install(Self.program, firstWorkoutDay: nil)

        let push = try #require(try routines(context).first { $0.seedKey == Self.push })
        let supersets = Dictionary(grouping: push.routineExercisesList.filter(\.isInSuperset)) { $0.supersetId }
        let pairs = Set(supersets.values.map { members in
            members.sorted { $0.supersetOrder < $1.supersetOrder }.compactMap(\.exercise?.seedKey)
        })
        #expect(pairs == [
            ["seed.exercise.tricep_pushdown", "seed.exercise.dumbbell_lateral_raise"],
            ["seed.exercise.overhead_tricep_extension", "seed.exercise.cable_lateral_raise"],
        ])
    }

    // MARK: - Plan

    @Test
    func eachRoutineRepeatsEveryFiveDaysWithOffsetsZeroOneThree() throws {
        let context = try makeContext()

        try installer(context).install(Self.program, firstWorkoutDay: Self.firstDay)

        let installed = try routines(context)
        for (key, offset) in [(Self.push, 0), (Self.pull, 1), (Self.legs, 3)] {
            let schedule = try #require(installed.first { $0.seedKey == key }?.schedule)
            #expect(schedule.type == .everyNDays)
            #expect(schedule.intervalDays == 5)
            #expect(schedule.startDate == Self.day(offset))
        }
    }

    @Test
    func restoringPullAndLegsStartsPullOnTheChosenDay() throws {
        let context = try makeContext()
        let installer = installer(context)
        try installer.install(Self.program, firstWorkoutDay: nil)
        for routine in try routines(context) where routine.seedKey != Self.push {
            context.delete(routine)
        }
        try context.save()

        #expect(try installer.install(Self.program, firstWorkoutDay: Self.firstDay) == 2)

        let installed = try routines(context)
        #expect(installed.count == 3)
        #expect(installed.first { $0.seedKey == Self.push }?.schedule == nil)
        #expect(installed.first { $0.seedKey == Self.pull }?.schedule?.startDate == Self.day(0))
        #expect(installed.first { $0.seedKey == Self.legs }?.schedule?.startDate == Self.day(2))
    }

    @Test
    func timelineRepeatsPushPullRestLegsRest() {
        let days = RoutineProgramSchedule.timeline(for: Self.program, from: Self.firstDay, dayCount: 14, calendar: Self.calendar)
        let cycle: [String?] = [Self.push, Self.pull, nil, Self.legs, nil]
        #expect(days.map(\.routineSeedKey) == Array((cycle + cycle + cycle).prefix(14)))
    }

    // MARK: - Display models

    @Test
    func pplDetailShowsSessionLengthAndFullBodyLinksToIt() {
        let viewModel = ProgramLibraryViewModel(
            installer: RoutineProgramInstaller(modelContext: ModelContext(InMemoryModelContainer.make())),
            proEntitlements: StubProEntitlements(state: .free),
            isGatingEnabled: true
        )
        let ppl = viewModel.summary(withId: "ppl")
        #expect(ppl?.detailStats == ppl?.libraryStats)
        #expect(ppl?.detailStats.last?.label == "routine_programs.stat.per_session".localized)
        let letter = { (key: String) -> String? in "\(key).short".localized }
        let expectedPattern: [String?] = [letter(Self.push), letter(Self.pull), nil, letter(Self.legs), nil, letter(Self.push), letter(Self.pull)]
        #expect(viewModel.shelfCards.first { $0.id == "ppl" }?.pattern.map(\.label) == expectedPattern)

        let fullBody = viewModel.summary(withId: "full_body")
        #expect(fullBody?.detailStats.last?.value == "routine_programs.full_body.stat.length".localized)
        let links = fullBody?.guidanceRules.compactMap(\.link) ?? []
        #expect(links.map(\.programId) == ["ppl"])
    }
}
