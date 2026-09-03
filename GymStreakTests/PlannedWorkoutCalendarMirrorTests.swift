//
//  PlannedWorkoutCalendarMirrorTests.swift
//  GymStreakTests
//
//  What actually reaches the calendar gateway: which routines contribute
//  occurrences, that the opt-in is the whole gate, that a failing calendar never
//  costs the user their plan — and that a plan edit triggers a pass at all.
//  The gateway itself is a fake, so no `EKEventStore` is constructed.
//

import Testing
import SwiftData
import Foundation
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct PlannedWorkoutCalendarMirrorTests {

    // MARK: - Harness

    private struct Harness {
        let context: ModelContext
        let preference: CalendarSyncPreference
        let sync: FakeWorkoutCalendarSync
        let mirror: PlannedWorkoutCalendarMirror
        let viewModel: RoutinesViewModel

        @discardableResult
        func makeRoutine(
            named name: String,
            type: RoutineScheduleType? = .everyNDays,
            intervalDays: Int = 5,
            weekdays: Set<Int> = [],
            startDate: Date = Date(),
            isActive: Bool = true
        ) -> Routine {
            let routine = Routine(name: name)
            context.insert(routine)
            if let type {
                let schedule = RoutineSchedule(
                    type: type,
                    intervalDays: intervalDays,
                    weekdays: weekdays,
                    startDate: startDate
                )
                schedule.isActive = isActive
                schedule.routine = routine
                context.insert(schedule)
            }
            return routine
        }
    }

    private static func throwawayDefaults() -> UserDefaults {
        let suiteName = "test.calendar_mirror.\(UUID().uuidString)"
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        return UserDefaults(suiteName: suiteName)!
    }

    private func makeHarness(syncEnabled: Bool = true) -> Harness {
        let context = ModelContext(InMemoryModelContainer.make())
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let preference = CalendarSyncPreference(defaults: Self.throwawayDefaults())
        preference.isCalendarSyncEnabled = syncEnabled
        let sync = FakeWorkoutCalendarSync()
        let mirror = PlannedWorkoutCalendarMirror(
            routineRepository: routineRepository,
            workoutSessionRepository: sessionRepository,
            preference: preference,
            sync: sync
        )
        let viewModel = RoutinesViewModel(
            routineRepository: routineRepository,
            workoutSessionRepository: sessionRepository,
            watchSync: MockWatchSyncServicing(),
            proEntitlements: StubProEntitlements(state: .subscription),
            paywalls: RecordingPaywallPresenter(),
            calendarMirror: mirror,
            isGatingEnabled: false
        )
        return Harness(
            context: context,
            preference: preference,
            sync: sync,
            mirror: mirror,
            viewModel: viewModel
        )
    }

    // MARK: - What gets mirrored

    @Test("A cadence plan contributes its next occurrences, agreeing with the sheet's preview")
    func cadencePlanIsMirrored() throws {
        let harness = makeHarness()
        let start = Date()
        let routine = harness.makeRoutine(named: "Push", intervalDays: 5, startDate: start)

        harness.mirror.reconcile()

        let batch = try #require(harness.sync.mirroredOccurrences.last)
        #expect(batch.count == PlannedWorkoutOccurrenceBuilder.horizonPerRoutine)
        #expect(batch.allSatisfy { $0.routineId == routine.id })
        #expect(batch.allSatisfy { $0.title.contains("Push") })
        // The very same helper the planning sheet's "next sessions" preview uses.
        let expected = WorkoutPlanningService.upcomingCadenceDates(
            startDate: start,
            lastCompleted: nil,
            intervalDays: 5,
            count: PlannedWorkoutOccurrenceBuilder.horizonPerRoutine
        )
        #expect(batch.map(\.day) == expected)
    }

    @Test("An unplanned, a paused and a weekday routine each contribute nothing")
    func unmirroredRoutines() throws {
        let harness = makeHarness()
        harness.makeRoutine(named: "Unplanned", type: nil)
        harness.makeRoutine(named: "Paused", isActive: false)
        // Fixed-weekday plans become a real recurrence rule in a later slice;
        // until then they are deliberately not mirrored as one-shot events.
        harness.makeRoutine(named: "Split", type: .weekdays, weekdays: [1, 3, 5])

        harness.mirror.reconcile()

        #expect(try #require(harness.sync.mirroredOccurrences.last).isEmpty)
    }

    @Test("Two planned routines each get their own occurrences")
    func twoRoutinesAreBothMirrored() throws {
        let harness = makeHarness()
        let push = harness.makeRoutine(named: "Push", intervalDays: 3)
        let pull = harness.makeRoutine(named: "Pull", intervalDays: 7)

        harness.mirror.reconcile()

        let batch = try #require(harness.sync.mirroredOccurrences.last)
        let horizon = PlannedWorkoutOccurrenceBuilder.horizonPerRoutine
        #expect(batch.filter { $0.routineId == push.id }.count == horizon)
        #expect(batch.filter { $0.routineId == pull.id }.count == horizon)
        // Every occurrence is uniquely addressed, so nothing collides in the diff.
        #expect(Set(batch.map(\.marker)).count == batch.count)
    }

    // MARK: - The opt-in gate

    @Test("With the toggle off nothing is read and nothing is written")
    func optInGatesTheWholeMirror() {
        let harness = makeHarness(syncEnabled: false)
        harness.makeRoutine(named: "Push")

        harness.mirror.reconcile()

        #expect(harness.sync.mirroredOccurrences.isEmpty)
    }

    // MARK: - Failure

    @Test("A calendar that refuses the write is swallowed, not surfaced")
    func mirrorFailureIsSwallowed() async {
        let harness = makeHarness()
        harness.sync.mirrorError = WorkoutCalendarSyncError.calendarWriteFailed("nope")
        let routine = harness.makeRoutine(named: "Push")

        // The plan is the source of truth; a failed projection must not undo it.
        let saved = await harness.viewModel.setSchedule(
            for: routine, type: .everyNDays, intervalDays: 9, weekdays: [], referenceDate: .now
        )

        #expect(saved)
        #expect(routine.schedule?.intervalDays == 9)
    }

    // MARK: - Triggers

    @Test("Saving a plan reconciles the calendar")
    func settingAScheduleTriggersAPass() async throws {
        let harness = makeHarness()
        let routine = harness.makeRoutine(named: "Push", type: nil)

        await harness.viewModel.setSchedule(
            for: routine, type: .everyNDays, intervalDays: 4, weekdays: [], referenceDate: .now
        )

        let batch = try #require(harness.sync.mirroredOccurrences.last)
        #expect(batch.count == PlannedWorkoutOccurrenceBuilder.horizonPerRoutine)
    }

    @Test("Clearing a plan reconciles the calendar to nothing")
    func removingAScheduleTriggersAPass() async throws {
        let harness = makeHarness()
        let routine = harness.makeRoutine(named: "Push")

        await harness.viewModel.removeSchedule(from: routine)

        #expect(try #require(harness.sync.mirroredOccurrences.last).isEmpty)
    }

    @Test("Switching the toggle on fills the calendar straight away")
    func enablingSyncTriggersAPass() async throws {
        let harness = makeHarness(syncEnabled: false)
        harness.makeRoutine(named: "Push")
        let settings = CalendarSyncSettingsViewModel(
            preference: harness.preference,
            sync: harness.sync,
            mirror: harness.mirror
        )

        await settings.setEnabled(true)

        let batch = try #require(harness.sync.mirroredOccurrences.last)
        #expect(batch.count == PlannedWorkoutOccurrenceBuilder.horizonPerRoutine)
    }
}
