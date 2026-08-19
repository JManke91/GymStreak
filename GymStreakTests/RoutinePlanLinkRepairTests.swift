//
//  RoutinePlanLinkRepairTests.swift
//  GymStreakTests
//
//  `RoutinePlanLinkRepair` deletes and re-inserts a user's training plan to
//  force CloudKit to re-export it with its routine reference (see
//  docs/workout-planning.md → "iCloud sync: why the plan is a to-many"). It
//  touches data that cannot be reconstructed if it goes wrong, so the
//  load-bearing assertions here are that every configured value survives the
//  round trip and that a second launch does nothing at all.
//

import Testing
import SwiftData
import Foundation
@testable import GymStreak

// Serialized: see SwiftDataRoutineRepositoryTests for why in-memory
// ModelContainer creation must not run concurrently within this process.
@Suite(.serialized)
@MainActor
struct RoutinePlanLinkRepairTests {

    @Test("A planned routine keeps every configured value and comes back linked")
    func repairPreservesPlanAndRelinks() async throws {
        let harness = try makeHarness()
        let routine = try harness.makePlannedRoutine(
            type: .weekdays,
            intervalDays: 4,
            weekdays: [2, 5],
            isActive: false
        )
        let original = try #require(routine.schedule)
        let originalID = original.id
        let originalCreatedAt = original.createdAt
        let originalStartDate = original.startDate

        await harness.repair.runIfNeeded()

        let repaired = try #require(routine.schedule)
        #expect(repaired.id == originalID)
        #expect(repaired.createdAt == originalCreatedAt)
        #expect(repaired.startDate == originalStartDate)
        #expect(repaired.type == .weekdays)
        #expect(repaired.intervalDays == 4)
        #expect(repaired.weekdays == [2, 5])
        #expect(repaired.isActive == false)
        // The point of the exercise: the child carries the link, which is the
        // side CloudKit actually mirrors.
        #expect(repaired.routine === routine)
        #expect(routine.schedules?.count == 1)
    }

    @Test("The plan is a genuinely new row, so mirroring has a change to export")
    func repairReplacesTheRow() async throws {
        let harness = try makeHarness()
        let routine = try harness.makePlannedRoutine()
        let original = try #require(routine.schedule)

        await harness.repair.runIfNeeded()

        let replacement = try #require(routine.schedule)
        #expect(replacement !== original)
    }

    @Test("A second launch leaves the plan untouched")
    func repairIsIdempotent() async throws {
        let harness = try makeHarness()
        let routine = try harness.makePlannedRoutine()

        await harness.repair.runIfNeeded()
        let afterFirstRun = try #require(routine.schedule)

        await harness.repair.runIfNeeded()

        let afterSecondRun = try #require(routine.schedule)
        #expect(afterSecondRun === afterFirstRun)
        #expect(routine.schedules?.count == 1)
    }

    @Test("An unplanned routine is left alone")
    func repairSkipsUnplannedRoutines() async throws {
        let harness = try makeHarness()
        let routine = Routine(name: "Unplanned")
        harness.context.insert(routine)
        try harness.context.save()

        await harness.repair.runIfNeeded()

        #expect(routine.schedule == nil)
        #expect(routine.schedules?.isEmpty ?? true)
    }

    // MARK: - Harness

    private struct Harness {
        let context: ModelContext
        let repair: RoutinePlanLinkRepair
        let sync: StubCloudSyncStatus

        func makePlannedRoutine(
            type: RoutineScheduleType = .everyNDays,
            intervalDays: Int = 5,
            weekdays: Set<Int> = [],
            isActive: Bool = true
        ) throws -> Routine {
            let routine = Routine(name: "Pull")
            context.insert(routine)
            let schedule = RoutineSchedule(
                type: type,
                intervalDays: intervalDays,
                weekdays: weekdays,
                startDate: Date(timeIntervalSince1970: 1_700_000_000)
            )
            schedule.isActive = isActive
            schedule.routine = routine
            context.insert(schedule)
            try context.save()
            return routine
        }
    }

    private func makeHarness() throws -> Harness {
        let context = ModelContext(InMemoryModelContainer.make())
        // A per-test suite keeps the one-shot flag out of `UserDefaults.standard`,
        // so these tests neither leak into each other nor into the app's domain.
        let suiteName = "RoutinePlanLinkRepairTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let sync = StubCloudSyncStatus.synced()
        return Harness(
            context: context,
            repair: RoutinePlanLinkRepair(
                modelContext: context,
                cloudSyncStatus: sync,
                defaults: defaults
            ),
            sync: sync
        )
    }
}

// The one-shot flag must not be recorded over a store that simply has not
// imported anything yet — otherwise the device that most needs the repair skips
// it forever. This is the trap `DefaultContentSeeder` documents for its own
// version flag.
@Suite(.serialized)
@MainActor
struct RoutinePlanLinkRepairGatingTests {

    private static let flagKey = "routinePlanLinkRepairVersion"

    @Test("An empty store leaves the flag clear so a later launch still repairs")
    func emptyStoreDoesNotStrandTheFlag() async throws {
        let fixture = try makeFixture()

        await fixture.repair.runIfNeeded()
        #expect(fixture.defaults.integer(forKey: Self.flagKey) == 0)

        // The plan arrives afterwards, as a CloudKit import would.
        let routine = Routine(name: "Legs")
        fixture.context.insert(routine)
        let schedule = RoutineSchedule(type: .everyNDays, intervalDays: 3)
        schedule.routine = routine
        fixture.context.insert(schedule)
        try fixture.context.save()

        await fixture.repair.runIfNeeded()

        #expect(fixture.defaults.integer(forKey: Self.flagKey) == 1)
        #expect(try #require(routine.schedule).routine === routine)
    }

    // Deleting an orphan would export that delete and destroy the plan on the
    // device that still holds it linked locally — the only good copy. The fix
    // must leave orphans alone; the owning device's own repair retires them.
    @Test("A schedule imported without its routine is preserved, never deleted")
    func orphanedScheduleIsPreserved() async throws {
        let fixture = try makeFixture()
        let orphan = RoutineSchedule(type: .everyNDays, intervalDays: 3)
        fixture.context.insert(orphan)
        try fixture.context.save()

        await fixture.repair.runIfNeeded()

        let remaining = try fixture.context.fetch(FetchDescriptor<RoutineSchedule>())
        #expect(remaining.count == 1)
        #expect(remaining.first === orphan)
    }

    @Test("With iCloud off nothing is touched and the flag stays clear")
    func syncOffDoesNothing() async throws {
        let fixture = try makeFixture(sync: StubCloudSyncStatus(initial: .off))
        let routine = Routine(name: "Push")
        fixture.context.insert(routine)
        let schedule = RoutineSchedule(type: .everyNDays, intervalDays: 7)
        schedule.routine = routine
        fixture.context.insert(schedule)
        try fixture.context.save()

        await fixture.repair.runIfNeeded()

        // Same object, so no delete/re-insert happened at all.
        #expect(try #require(routine.schedule) === schedule)
        #expect(fixture.defaults.integer(forKey: Self.flagKey) == 0)
    }

    // The gate must be the *state*, not `lastSuccessfulSync`: the monitor restores
    // that timestamp from UserDefaults at launch, so on any device that has ever
    // synced it is non-nil before this session transfers anything. Gating on it
    // would let the repair delete rows mid-import.
    @Test("A device mid-sync is not repaired, even with a previous successful sync")
    func syncingWithAPriorSuccessDoesNotRepair() async throws {
        let sync = StubCloudSyncStatus(
            initial: CloudSyncStatus(state: .syncing, lastSuccessfulSync: Date())
        )
        let fixture = try makeFixture(sync: sync)
        let routine = Routine(name: "Pull")
        fixture.context.insert(routine)
        let schedule = RoutineSchedule(type: .everyNDays, intervalDays: 4)
        schedule.routine = routine
        fixture.context.insert(schedule)
        try fixture.context.save()

        let task = Task { await fixture.repair.runIfNeeded() }
        await sync.waitForSubscriber()

        #expect(try #require(routine.schedule) === schedule)
        #expect(fixture.defaults.integer(forKey: Self.flagKey) == 0)

        // Quiescence arrives: now it repairs.
        sync.emit(CloudSyncStatus(state: .upToDate, lastSuccessfulSync: Date()))
        await task.value

        #expect(try #require(routine.schedule) !== schedule)
        #expect(fixture.defaults.integer(forKey: Self.flagKey) == 1)
    }

    // The context is shared. Another component's staged work must not be
    // committed by this pass's save, nor discarded by its rollback.
    @Test("Unsaved work staged by anything else defers the repair")
    func unsavedWorkOnTheContextDefersTheRepair() async throws {
        let fixture = try makeFixture()
        let routine = Routine(name: "Push")
        fixture.context.insert(routine)
        let schedule = RoutineSchedule(type: .everyNDays, intervalDays: 6)
        schedule.routine = routine
        fixture.context.insert(schedule)
        try fixture.context.save()

        // Someone else stages an insert and has not saved it.
        fixture.context.insert(Exercise(name: "Staged"))
        #expect(fixture.context.hasChanges)

        await fixture.repair.runIfNeeded()

        #expect(try #require(routine.schedule) === schedule)
        #expect(fixture.defaults.integer(forKey: Self.flagKey) == 0)
        // Still pending — neither committed nor rolled back by the repair.
        #expect(fixture.context.hasChanges)
    }

    // MARK: - Fixture

    private struct Fixture {
        let context: ModelContext
        let repair: RoutinePlanLinkRepair
        let defaults: UserDefaults
    }

    private func makeFixture(sync: StubCloudSyncStatus? = nil) throws -> Fixture {
        let context = ModelContext(InMemoryModelContainer.make())
        let suiteName = "RoutinePlanLinkRepairGating.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return Fixture(
            context: context,
            repair: RoutinePlanLinkRepair(
                modelContext: context,
                cloudSyncStatus: sync ?? .synced(),
                defaults: defaults
            ),
            defaults: defaults
        )
    }
}
