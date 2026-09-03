//
//  WeekdayScheduleHintTests.swift
//  GymStreakTests
//
//  P9's discovery surface (ticket 05): the narrow cohort the hint is for, the
//  much larger cohort it must stay silent for, and the rule that it never
//  presents anything on its own. The trap this exists to avoid is nudging a
//  user whose weekday rotates *by design*, so the multiple-of-7 boundary is
//  pinned in both directions.
//

import Testing
import SwiftData
import Foundation
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct WeekdayScheduleHintTests {

    // MARK: - Fixtures

    private static let calendar = HistoryStatsService.isoGermanCalendar()

    private static func day(_ offsetFromToday: Int) -> Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: offsetFromToday, to: today) ?? today
    }

    /// A schedule whose start date is a whole number of weeks back, so its start
    /// weekday is today's — which makes "has it drifted?" a question about the
    /// completion alone rather than about the calendar the suite happens to run on.
    private func schedule(
        type: RoutineScheduleType = .everyNDays,
        intervalDays: Int,
        startOffset: Int = -28,
        isActive: Bool = true
    ) -> RoutineSchedule {
        let schedule = RoutineSchedule(
            type: type,
            intervalDays: intervalDays,
            weekdays: type == .weekdays ? [1, 3, 5] : [],
            startDate: Self.day(startOffset)
        )
        schedule.isActive = isActive
        return schedule
    }

    // MARK: - The cohort the hint is for

    @Test("A weekly plan that slipped off its day names the day it started on")
    func driftedWeeklyPlanIsHinted() throws {
        // Started on today's weekday; last trained yesterday, so the next due day
        // is a week from yesterday — one weekday earlier than intended.
        let weekly = schedule(intervalDays: 7)

        let hinted = try #require(WeekdayScheduleHintPolicy.driftedStartWeekday(
            for: weekly, lastCompleted: Self.day(-1)
        ))

        let expected = WorkoutPlanningService.isoWeekday(
            from: weekly.startDate, calendar: Self.calendar
        )
        #expect(hinted == expected)
        // The day offered is the intended one, not the drifted one.
        let due = try #require(WorkoutPlanningService.nextDue(for: weekly, lastCompleted: Self.day(-1)))
        #expect(hinted != WorkoutPlanningService.isoWeekday(from: due, calendar: Self.calendar))
    }

    @Test("A fortnightly plan counts as a weekly rhythm too")
    func fortnightlyPlanIsHinted() {
        let fortnightly = schedule(intervalDays: 14)

        #expect(WeekdayScheduleHintPolicy.driftedStartWeekday(
            for: fortnightly, lastCompleted: Self.day(-1)
        ) != nil)
    }

    // MARK: - The trap: intervals that rotate by design

    @Test(
        "A non-weekly interval is never hinted, however far it has moved",
        arguments: [1, 2, 3, 4, 5, 6, 8, 9, 10, 13, 15, 30]
    )
    func nonWeeklyIntervalsAreNeverHinted(intervalDays: Int) {
        let rotating = schedule(intervalDays: intervalDays)

        // Every completion offset in a fortnight — the weekday has certainly
        // moved for most of these, and it is *supposed* to.
        for offset in 1...14 {
            #expect(WeekdayScheduleHintPolicy.driftedStartWeekday(
                for: rotating, lastCompleted: Self.day(-offset)
            ) == nil)
        }
    }

    @Test("A zero interval is not a weekly rhythm, despite passing the modulo")
    func zeroIntervalIsNotHinted() {
        let broken = schedule(intervalDays: 0)

        #expect(WeekdayScheduleHintPolicy.driftedStartWeekday(
            for: broken, lastCompleted: Self.day(-1)
        ) == nil)
    }

    // MARK: - Silence conditions

    @Test("A weekly plan still on its original day says nothing")
    func undriftedPlanIsNotHinted() {
        let weekly = schedule(intervalDays: 7)

        // Trained exactly on the plan's own weekday, so the next due day is the
        // same weekday it started on.
        #expect(WeekdayScheduleHintPolicy.driftedStartWeekday(
            for: weekly, lastCompleted: Self.day(-7)
        ) == nil)
        // ...and with no completion at all, the cadence still runs off the start
        // date, so it has not moved either.
        #expect(WeekdayScheduleHintPolicy.driftedStartWeekday(
            for: weekly, lastCompleted: nil
        ) == nil)
    }

    @Test("The hint disappears by itself once the user re-anchors")
    func hintClearsWhenTheUserTrainsOnTheIntendedDay() {
        let weekly = schedule(intervalDays: 7)

        #expect(WeekdayScheduleHintPolicy.driftedStartWeekday(
            for: weekly, lastCompleted: Self.day(-1)
        ) != nil)
        // Nothing is reset and no state is written — training on the intended
        // weekday is enough, which is the whole point of the stateless predicate.
        #expect(WeekdayScheduleHintPolicy.driftedStartWeekday(
            for: weekly, lastCompleted: Self.day(-14)
        ) == nil)
    }

    @Test("A weekday plan and a paused plan each say nothing")
    func ineligibleSchedulesAreNotHinted() {
        #expect(WeekdayScheduleHintPolicy.driftedStartWeekday(
            for: schedule(type: .weekdays, intervalDays: 7), lastCompleted: Self.day(-1)
        ) == nil)
        #expect(WeekdayScheduleHintPolicy.driftedStartWeekday(
            for: schedule(intervalDays: 7, isActive: false), lastCompleted: Self.day(-1)
        ) == nil)
    }

    // MARK: - Eligibility, through the ViewModel

    @Test("An unplanned routine has nothing to hint at")
    func unplannedRoutineIsNotHinted() {
        let harness = makeHarness()
        let routine = harness.makeRoutine(intervalDays: nil)

        #expect(harness.viewModel.weekdayScheduleHintDay(for: routine) == nil)
    }

    @Test("A free user with a drifted weekly plan sees the hint")
    func freeUserSeesTheHint() {
        let harness = makeHarness(state: .free)
        let routine = harness.makeRoutine(intervalDays: 7)
        harness.completeWorkout(for: routine, on: Self.day(-1))

        #expect(harness.viewModel.weekdayScheduleHintDay(for: routine) != nil)
        // Drawing it presents nothing — §8 caps placement C on genuine intent.
        #expect(harness.paywalls.presentedPlacements.isEmpty)
    }

    @Test(
        "Nobody the gate does not apply to is nudged",
        arguments: [ProEntitlementState.subscription, .lifetime, .founder]
    )
    func entitledUsersAreNeverHinted(state: ProEntitlementState) {
        let harness = makeHarness(state: state)
        let routine = harness.makeRoutine(intervalDays: 7)
        harness.completeWorkout(for: routine, on: Self.day(-1))

        #expect(harness.viewModel.weekdayScheduleHintDay(for: routine) == nil)
    }

    @Test("With the kill switch off nobody is nudged, free users included")
    func gatingDisabledSilencesTheHint() {
        let harness = makeHarness(state: .free, isGatingEnabled: false)
        let routine = harness.makeRoutine(intervalDays: 7)
        harness.completeWorkout(for: routine, on: Self.day(-1))

        #expect(harness.viewModel.weekdayScheduleHintDay(for: routine) == nil)
    }

    // MARK: - The tap

    @Test("Tapping raises the existing weekdaySchedule placement, exactly once")
    func tappingRaisesTheExistingPlacement() {
        let harness = makeHarness(state: .free)
        let routine = harness.makeRoutine(intervalDays: 7)
        harness.completeWorkout(for: routine, on: Self.day(-1))
        #expect(harness.viewModel.weekdayScheduleHintDay(for: routine) != nil)

        // What `WeekdayScheduleHintRow`'s action calls.
        let allowed = harness.viewModel.requestWeekdaySchedule()

        #expect(allowed == false)
        #expect(harness.paywalls.presentedPlacements == [.weekdaySchedule])
        // Nothing was written: the routine keeps the plan it had.
        #expect(routine.schedule?.type == .everyNDays)
        #expect(routine.schedule?.intervalDays == 7)
    }

    // MARK: - Harness

    @MainActor
    private struct Harness {
        let context: ModelContext
        let viewModel: RoutinesViewModel
        let paywalls: RecordingPaywallPresenter

        func makeRoutine(intervalDays: Int?) -> Routine {
            let routine = Routine(name: "Leg Day")
            context.insert(routine)
            if let intervalDays {
                let schedule = RoutineSchedule(
                    type: .everyNDays,
                    intervalDays: intervalDays,
                    weekdays: [],
                    startDate: WeekdayScheduleHintTests.day(-28)
                )
                schedule.routine = routine
                context.insert(schedule)
            }
            try? context.save()
            viewModel.fetchRoutines()
            return routine
        }

        func completeWorkout(for routine: Routine, on day: Date) {
            let session = WorkoutSession(routine: routine)
            session.startTime = day
            session.endTime = day.addingTimeInterval(3600)
            context.insert(session)
            try? context.save()
            viewModel.fetchRoutines()
        }
    }

    /// Gating **on** by default, unlike the shipped app: with the real
    /// `ProGating.isEnabled` the silence assertions would pass for the wrong
    /// reason. Same arrangement as `ScheduleGatingTests`.
    private func makeHarness(
        state: ProEntitlementState = .free,
        isGatingEnabled: Bool = true
    ) -> Harness {
        let context = ModelContext(InMemoryModelContainer.make())
        let paywalls = RecordingPaywallPresenter()
        let viewModel = RoutinesViewModel(
            routineRepository: SwiftDataRoutineRepository(modelContext: context),
            workoutSessionRepository: SwiftDataWorkoutSessionRepository(modelContext: context),
            watchSync: MockWatchSyncServicing(),
            proEntitlements: StubProEntitlements(state: state),
            paywalls: paywalls,
            isGatingEnabled: isGatingEnabled
        )
        return Harness(context: context, viewModel: viewModel, paywalls: paywalls)
    }
}
