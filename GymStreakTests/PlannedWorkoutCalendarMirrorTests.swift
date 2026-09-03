//
//  PlannedWorkoutCalendarMirrorTests.swift
//  GymStreakTests
//
//  What actually reaches the calendar gateway: which routines contribute which
//  shape — a cadence plan's rolling window, a weekday plan's single repeating
//  series — that the opt-in is the whole gate, that a failing calendar never
//  costs the user their plan, that switching shapes swaps the representation
//  cleanly, and that a plan edit triggers a pass at all.
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
        let entitlements: StubProEntitlements

        /// Lets the reconcile `fetchRoutines()` defers into its own main-actor
        /// turn actually run. The pass is deliberately off the routines list's
        /// critical path, so nothing about it is observable until the test yields.
        /// Three, not one: a notification-driven refresh costs a hop to the main
        /// actor, then the coalescing slot's own hop, then the reconcile the
        /// refresh defers — and each is a separate turn.
        func settle() async {
            await Task.yield()
            await Task.yield()
            await Task.yield()
        }

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

        /// A finished workout — the plan-adjacent event that fires a pass.
        func completeWorkout(for routine: Routine, on day: Date) {
            let session = WorkoutSession(routine: routine)
            session.startTime = day
            session.endTime = day.addingTimeInterval(3600)
            context.insert(session)
            try? context.save()
        }
    }

    private static func throwawayDefaults() -> UserDefaults {
        let suiteName = "test.calendar_mirror.\(UUID().uuidString)"
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        return UserDefaults(suiteName: suiteName)!
    }

    private func makeHarness(
        syncEnabled: Bool = true,
        entitlementState: ProEntitlementState = .subscription,
        isGatingEnabled: Bool = false
    ) -> Harness {
        let context = ModelContext(InMemoryModelContainer.make())
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let preference = CalendarSyncPreference(defaults: Self.throwawayDefaults())
        preference.isCalendarSyncEnabled = syncEnabled
        let sync = FakeWorkoutCalendarSync()
        // The state the app is actually in once sync is on: access granted and a
        // calendar owned. Both are the gateway's own guards, so a fake left in
        // `.notDetermined` would exercise the revoked-access path by accident.
        sync.accessStatus = .fullAccess
        sync.appCalendarIdentifier = "test-calendar"
        let mirror = PlannedWorkoutCalendarMirror(
            routineRepository: routineRepository,
            workoutSessionRepository: sessionRepository,
            preference: preference,
            sync: sync
        )
        let entitlements = StubProEntitlements(state: entitlementState)
        let viewModel = RoutinesViewModel(
            routineRepository: routineRepository,
            workoutSessionRepository: sessionRepository,
            watchSync: MockWatchSyncServicing(),
            proEntitlements: entitlements,
            paywalls: RecordingPaywallPresenter(),
            calendarMirror: mirror,
            isGatingEnabled: isGatingEnabled
        )
        return Harness(
            context: context,
            preference: preference,
            sync: sync,
            mirror: mirror,
            viewModel: viewModel,
            entitlements: entitlements
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
        #expect(batch.count == PlannedWorkoutCalendarStateBuilder.horizonPerRoutine)
        #expect(batch.allSatisfy { $0.routineId == routine.id })
        #expect(batch.allSatisfy { $0.title.contains("Push") })
        // The very same helper the planning sheet's "next sessions" preview uses.
        let expected = WorkoutPlanningService.upcomingCadenceDates(
            startDate: start,
            lastCompleted: nil,
            intervalDays: 5,
            count: PlannedWorkoutCalendarStateBuilder.horizonPerRoutine
        )
        #expect(batch.map(\.day) == expected)
    }

    @Test("An unplanned, a paused and an empty weekday routine each contribute nothing")
    func unmirroredRoutines() throws {
        let harness = makeHarness()
        harness.makeRoutine(named: "Unplanned", type: nil)
        harness.makeRoutine(named: "Paused", isActive: false)
        // A paused weekday plan is no more mirrored than a paused cadence, and a
        // weekday plan with no day selected is not a plan at all.
        harness.makeRoutine(named: "Paused split", type: .weekdays, weekdays: [1, 3], isActive: false)
        harness.makeRoutine(named: "No days", type: .weekdays, weekdays: [])

        harness.mirror.reconcile()

        let state = try #require(harness.sync.mirroredStates.last)
        #expect(state.isEmpty)
    }

    @Test("Two planned routines each get their own occurrences")
    func twoRoutinesAreBothMirrored() throws {
        let harness = makeHarness()
        let push = harness.makeRoutine(named: "Push", intervalDays: 3)
        let pull = harness.makeRoutine(named: "Pull", intervalDays: 7)

        harness.mirror.reconcile()

        let batch = try #require(harness.sync.mirroredOccurrences.last)
        let horizon = PlannedWorkoutCalendarStateBuilder.horizonPerRoutine
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
        await harness.settle()

        let batch = try #require(harness.sync.mirroredOccurrences.last)
        #expect(batch.count == PlannedWorkoutCalendarStateBuilder.horizonPerRoutine)
    }

    @Test("Clearing a plan reconciles the calendar to nothing")
    func removingAScheduleTriggersAPass() async throws {
        let harness = makeHarness()
        let routine = harness.makeRoutine(named: "Push")

        await harness.viewModel.removeSchedule(from: routine)
        await harness.settle()

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
        #expect(batch.count == PlannedWorkoutCalendarStateBuilder.horizonPerRoutine)
    }

    // MARK: - The weekday series

    @Test("A weekday plan is mirrored as one repeating series, not as dated events")
    func weekdayPlanIsMirroredAsASeries() throws {
        let harness = makeHarness()
        let routine = harness.makeRoutine(named: "Split", type: .weekdays, weekdays: [1, 3, 5])

        harness.mirror.reconcile()

        let state = try #require(harness.sync.mirroredStates.last)
        #expect(state.occurrences.isEmpty)
        let series = try #require(state.series.first)
        #expect(state.series.count == 1)
        #expect(series.routineId == routine.id)
        #expect(series.weekdays == [1, 3, 5])
        #expect(series.title.contains("Split"))
    }

    @Test("The series starts on the first upcoming occurrence the routine card shows")
    func seriesStartsOnNextDue() throws {
        let harness = makeHarness()
        let routine = harness.makeRoutine(named: "Split", type: .weekdays, weekdays: [1, 3, 5])
        let schedule = try #require(routine.schedule)

        harness.mirror.reconcile()

        let series = try #require(harness.sync.mirroredStates.last?.series.first)
        // The very helper that labels the card and orders the list — not a
        // second forward scan of the calendar's own.
        let expected = try #require(
            WorkoutPlanningService.nextDue(for: schedule, lastCompleted: nil)
        )
        #expect(series.firstDay == expected)
        let calendar = HistoryStatsService.isoGermanCalendar()
        #expect(series.weekdays.contains(
            WorkoutPlanningService.isoWeekday(from: series.firstDay, calendar: calendar)
        ))
    }

    @Test("A cadence routine and a weekday routine are mirrored in their own shapes")
    func bothShapesAreMirroredTogether() throws {
        let harness = makeHarness()
        let push = harness.makeRoutine(named: "Push", intervalDays: 3)
        let split = harness.makeRoutine(named: "Split", type: .weekdays, weekdays: [2, 4])

        harness.mirror.reconcile()

        let state = try #require(harness.sync.mirroredStates.last)
        #expect(state.occurrences.allSatisfy { $0.routineId == push.id })
        #expect(state.occurrences.count == PlannedWorkoutCalendarStateBuilder.horizonPerRoutine)
        #expect(state.series.map(\.routineId) == [split.id])
    }

    @Test("An unchanged weekday plan re-reconciles to exactly the same state")
    func weekdayPlanIsIdempotent() throws {
        let harness = makeHarness()
        harness.makeRoutine(named: "Split", type: .weekdays, weekdays: [1, 3, 5])

        harness.mirror.reconcile()
        let first = try #require(harness.sync.mirroredStates.last)
        // A second pass is short-circuited entirely: the desired state has not
        // moved, so no EventKit call is made at all.
        harness.mirror.reconcile()

        #expect(harness.sync.mirroredStates.count == 1)
        let actions = PlannedWorkoutCalendarReconciler.actions(
            desired: first,
            existing: first.series.enumerated().map { index, series in
                MirroredWorkoutEvent(
                    reference: index,
                    markerURL: series.marker,
                    recurringWeekdays: series.weekdays
                )
            }
        )
        #expect(actions.isEmpty)
    }

    // MARK: - Switching shapes

    @Test("Weekdays → cadence leaves a rolling window and no series")
    func switchingToCadenceSwapsTheRepresentation() async throws {
        let harness = makeHarness()
        let routine = harness.makeRoutine(named: "Split", type: .weekdays, weekdays: [1, 3, 5])
        harness.mirror.reconcile()
        #expect(try #require(harness.sync.mirroredStates.last).series.count == 1)

        await harness.viewModel.setSchedule(
            for: routine, type: .everyNDays, intervalDays: 4, weekdays: [1, 3, 5], referenceDate: .now
        )
        await harness.settle()

        let state = try #require(harness.sync.mirroredStates.last)
        #expect(state.series.isEmpty)
        #expect(state.occurrences.count == PlannedWorkoutCalendarStateBuilder.horizonPerRoutine)
    }

    @Test("Cadence → weekdays leaves a series and no one-shot events")
    func switchingToWeekdaysSwapsTheRepresentation() async throws {
        let harness = makeHarness()
        let routine = harness.makeRoutine(named: "Push", intervalDays: 4)
        harness.mirror.reconcile()
        #expect(try #require(harness.sync.mirroredStates.last).occurrences.isEmpty == false)

        await harness.viewModel.setSchedule(
            for: routine, type: .weekdays, intervalDays: 4, weekdays: [2, 4], referenceDate: .now
        )
        await harness.settle()

        let state = try #require(harness.sync.mirroredStates.last)
        #expect(state.occurrences.isEmpty)
        #expect(state.series.map(\.weekdays) == [[2, 4]])
    }

    @Test("Removing a weekday plan removes the series")
    func removingAWeekdayPlanClearsTheSeries() async throws {
        let harness = makeHarness()
        let routine = harness.makeRoutine(named: "Split", type: .weekdays, weekdays: [1, 3, 5])
        harness.mirror.reconcile()

        await harness.viewModel.removeSchedule(from: routine)
        await harness.settle()

        #expect(try #require(harness.sync.mirroredStates.last).isEmpty)
    }

    // MARK: - Entitlement (P9)

    @Test("A lapsed subscriber's weekday series is still maintained")
    func lapsedSubscriberKeepsTheirSeries() async throws {
        // Gating **on**, unlike the shipped app: with the real `ProGating`
        // this would pass for the wrong reason. Mirrors the arrangement in
        // GymStreakTests/ScheduleGatingTests.swift.
        let harness = makeHarness(entitlementState: .subscription, isGatingEnabled: true)
        let routine = harness.makeRoutine(named: "Split", type: nil)
        #expect(await harness.viewModel.setSchedule(
            for: routine, type: .weekdays, intervalDays: 3, weekdays: [1, 3, 5], referenceDate: .now
        ))
        await harness.settle()
        #expect(try #require(harness.sync.mirroredStates.last).series.count == 1)

        // The subscription lapses. Nothing about the plan changes — and nothing
        // about the calendar should either.
        harness.entitlements.state = .free
        harness.completeWorkout(for: routine, on: Date())
        harness.mirror.reconcile(revalidatingCalendar: true)

        let state = try #require(harness.sync.mirroredStates.last)
        let series = try #require(state.series.first)
        #expect(series.routineId == routine.id)
        #expect(series.weekdays == [1, 3, 5])
        // No `isPro` reaches the builder: the same routines and history produce
        // the same state whichever entitlement the user holds.
        #expect(state == PlannedWorkoutCalendarStateBuilder.state(
            routines: [routine],
            lastCompleted: [:]
        ))
    }
}
