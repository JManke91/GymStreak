//
//  RoutineProgramInstallerTests.swift
//  GymStreakTests
//
//  The install contract of docs/routine-programs.md: exact content, gap-filling,
//  re-created exercises, cadence-only plans, outside the cap, and surviving the
//  example seeder.
//

import Testing
import SwiftData
import Foundation
@testable import GymStreak

private final class EmptyVersionStore: SeedCatalogVersionStore, @unchecked Sendable {
    func version(forKey key: String) -> Int { 0 }
    func setVersion(_ version: Int, forKey key: String) {}
}

@Suite(.serialized)
@MainActor
struct RoutineProgramInstallerTests {

    private static let program = RoutineProgramCatalog.beginnerFullBody
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private static var wantedExerciseKeys: Set<String> {
        Set(program.routines.flatMap { $0.exercises.flatMap { [$0.exerciseSeedKey] + $0.alternativeSeedKeys } })
    }

    private func makeContext(omitting omitted: Set<String> = []) throws -> ModelContext {
        let context = ModelContext(InMemoryModelContainer.make())
        for row in SeedExerciseCatalog.entries where Self.wantedExerciseKeys.contains(row.seedKey) && !omitted.contains(row.seedKey) {
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
    func catalogOnlyReferencesSeedExercises() {
        let catalogKeys = Set(SeedExerciseCatalog.entries.map(\.seedKey))
        #expect(Self.wantedExerciseKeys.isSubset(of: catalogKeys))
    }

    @Test
    func freshInstallCreatesBothRoutinesWithTheExactContent() throws {
        let context = try makeContext()

        let inserted = try installer(context).install(Self.program, firstWorkoutDay: nil)

        #expect(inserted == 2)
        let installed = try routines(context)
        #expect(Set(installed.map(\.seedKey)) == ["seed.program.full_body.a", "seed.program.full_body.b"])

        for programRoutine in Self.program.routines {
            let routine = try #require(installed.first { $0.seedKey == programRoutine.seedKey })
            #expect(routine.name == programRoutine.seedKey.localized)
            #expect(routine.updatedAt == routine.createdAt)
            let slots = routine.routineExercisesList.sorted { $0.order < $1.order }
            #expect(slots.count == programRoutine.exercises.count)

            for (slot, expected) in zip(slots, programRoutine.exercises) {
                #expect(slot.exercise?.seedKey == expected.exerciseSeedKey)
                #expect(slot.targetRepMin == expected.repMin)
                #expect(slot.targetRepMax == expected.repMax)
                #expect(slot.setsList.count == expected.setCount)
                #expect(slot.setsList.allSatisfy { $0.reps == expected.repMin && $0.weight == 0 && $0.restTime == expected.restTime })
                #expect(slot.alternativesList.compactMap(\.exercise?.seedKey) == expected.alternativeSeedKeys)
                for alternative in slot.alternativesList {
                    #expect(alternative.targetRepMin == expected.repMin)
                    #expect(alternative.targetRepMax == expected.repMax)
                    #expect(alternative.setsList.count == expected.setCount)
                    #expect(alternative.setsList.allSatisfy { $0.reps == expected.repMin && $0.restTime == expected.restTime })
                }
            }
        }

        // Full Body A: lateral raise + pushdown are one superset, in that order.
        let routineA = try #require(installed.first { $0.seedKey == "seed.program.full_body.a" })
        let superset = routineA.routineExercisesList.filter(\.isInSuperset).sorted { $0.supersetOrder < $1.supersetOrder }
        #expect(superset.map { $0.exercise?.seedKey } == ["seed.exercise.dumbbell_lateral_raise", "seed.exercise.tricep_pushdown"])
        #expect(Set(superset.map(\.supersetId)).count == 1)
    }

    // MARK: - Gap-filling

    @Test
    func reinstallingIsANoOp() throws {
        let context = try makeContext()
        let installer = installer(context)
        try installer.install(Self.program, firstWorkoutDay: nil)
        let before = Set(try routines(context).map(\.id))

        let inserted = try installer.install(Self.program, firstWorkoutDay: nil)

        #expect(inserted == 0)
        #expect(Set(try routines(context).map(\.id)) == before)
    }

    @Test
    func reinstallAfterDeletingBRestoresOnlyB() throws {
        let context = try makeContext()
        let installer = installer(context)
        try installer.install(Self.program, firstWorkoutDay: nil)
        let routineA = try #require(try routines(context).first { $0.seedKey == "seed.program.full_body.a" })
        routineA.name = "My edited A"
        let routineB = try #require(try routines(context).first { $0.seedKey == "seed.program.full_body.b" })
        context.delete(routineB)
        try context.save()

        let inserted = try installer.install(Self.program, firstWorkoutDay: nil)

        #expect(inserted == 1)
        let after = try routines(context)
        #expect(after.count == 2)
        #expect(after.first { $0.seedKey == "seed.program.full_body.a" }?.id == routineA.id)
        #expect(after.first { $0.seedKey == "seed.program.full_body.a" }?.name == "My edited A")
        #expect(after.contains { $0.seedKey == "seed.program.full_body.b" })
    }

    @Test
    func aDeletedSeedExerciseIsRecreated() throws {
        let context = try makeContext(omitting: ["seed.exercise.lat_pulldown", "seed.exercise.goblet_squat"])

        try installer(context).install(Self.program, firstWorkoutDay: nil)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        #expect(exercises.filter { $0.seedKey == "seed.exercise.lat_pulldown" }.count == 1)
        let routineA = try #require(try routines(context).first { $0.seedKey == "seed.program.full_body.a" })
        #expect(routineA.routineExercisesList.count == 6)
        #expect(routineA.routineExercisesList.contains { $0.exercise?.seedKey == "seed.exercise.lat_pulldown" })
        let squat = try #require(routineA.routineExercisesList.first { $0.order == 0 })
        #expect(squat.alternativesList.compactMap(\.exercise?.seedKey) == ["seed.exercise.leg_press", "seed.exercise.goblet_squat"])
    }

    @Test
    func aUserExerciseWithTheCatalogNameIsReusedInsteadOfDuplicated() throws {
        let context = try makeContext(omitting: ["seed.exercise.lat_pulldown"])
        let own = Exercise(name: "seed.exercise.lat_pulldown".localized.uppercased())
        context.insert(own)
        try context.save()

        try installer(context).install(Self.program, firstWorkoutDay: nil)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        #expect(!exercises.contains { $0.seedKey == "seed.exercise.lat_pulldown" })
        let routineA = try #require(try routines(context).first { $0.seedKey == "seed.program.full_body.a" })
        #expect(routineA.routineExercisesList.contains { $0.exercise?.id == own.id })
    }

    // MARK: - Plan

    @Test
    func planningByRecoveryTimeWritesAnEveryFourDaysCadenceWithBTwoDaysLater() throws {
        let context = try makeContext()
        let firstDay = Self.calendar.date(from: DateComponents(year: 2026, month: 9, day: 27))!

        try installer(context).install(Self.program, firstWorkoutDay: firstDay)

        let installed = try routines(context)
        let scheduleA = try #require(installed.first { $0.seedKey == "seed.program.full_body.a" }?.schedule)
        let scheduleB = try #require(installed.first { $0.seedKey == "seed.program.full_body.b" }?.schedule)
        for schedule in [scheduleA, scheduleB] {
            #expect(schedule.type == .everyNDays)
            #expect(schedule.intervalDays == 4)
            #expect(schedule.isActive)
        }
        #expect(scheduleA.startDate == firstDay)
        #expect(scheduleB.startDate == Self.calendar.date(byAdding: .day, value: 2, to: firstDay))
    }

    @Test
    func noPlanIsWrittenWhenTheToggleIsOff() throws {
        let context = try makeContext()

        try installer(context).install(Self.program, firstWorkoutDay: nil)

        #expect(try routines(context).allSatisfy { ($0.schedules ?? []).isEmpty })
        #expect(try context.fetchCount(FetchDescriptor<RoutineSchedule>()) == 0)
    }

    @Test
    func thePlanIsNeverAWeekdayPlan() throws {
        let context = try makeContext()

        try installer(context).install(Self.program, firstWorkoutDay: Date())

        let schedules = try context.fetch(FetchDescriptor<RoutineSchedule>())
        #expect(schedules.count == 2)
        #expect(schedules.allSatisfy { $0.type != .weekdays && $0.weekdaysMask == 0 })
    }

    // MARK: - Cap and the example seeder

    @Test
    func installedRoutinesDoNotCountTowardTheCap() throws {
        let context = try makeContext()
        context.insert(Routine(name: "Push Day"))
        try context.save()

        try installer(context).install(Self.program, firstWorkoutDay: nil)

        #expect(RoutineCapPolicy.countableRoutineCount(in: try routines(context)) == 1)
    }

    @Test
    func installedRoutinesSurviveTheExampleSeeder() async throws {
        let context = try makeContext()
        let own = Routine(name: "Push Day")
        own.createdAt = Date().addingTimeInterval(-90 * 24 * 3600)
        own.updatedAt = own.createdAt
        context.insert(own)
        try context.save()
        try installer(context).install(Self.program, firstWorkoutDay: nil)

        let seeder = ExampleRoutineSeeder(
            modelContext: context,
            defaults: UserDefaults(suiteName: "RoutineProgramInstallerTests.\(UUID().uuidString)")!,
            cloudVersionStore: EmptyVersionStore(),
            historyStoreGate: .unshared()
        )
        await seeder.run()
        await seeder.cleanUpAfterImport()

        let keys = Set(try routines(context).map(\.seedKey))
        #expect(keys == ["", "seed.program.full_body.a", "seed.program.full_body.b"])
    }
}
