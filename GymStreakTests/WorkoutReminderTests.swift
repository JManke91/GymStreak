//
//  WorkoutReminderTests.swift
//  GymStreakTests
//
//  Ticket 03: the planned-session reminder and the permission seam in front of
//  it (docs/workout-reminders.md).
//
//  Three things carry the ticket. **The pre-prompt protects the one ask** — a
//  decline raises no system prompt at all, an install that already has
//  permission is never offered, and a decline can be revisited exactly once.
//  **The reminder agrees with the app** — it lands on the day
//  `WorkoutPlanningService` says is planned, for both schedule shapes, and on no
//  day at all when the plan is paused or absent. And **the cap is real** — one a
//  day, three a rolling week, enforced in one place that every reminder kind
//  passes through.
//
//  The notification centre is a fake throughout, so no system prompt is ever
//  raised and no request reaches `UNUserNotificationCenter`.
//

import Foundation
import SwiftData
import Testing
import UserNotifications
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct WorkoutReminderTests {

    private typealias Fixture = WorkoutReminderFixtures

    // MARK: - The frequency cap

    @Test("One reminder a day, whatever asks for it")
    func capAllowsOneReminderPerDay() {
        let calendar = HistoryStatsService.isoGermanCalendar()
        let monday = Fixture.day("2026-06-01")

        #expect(ReminderFrequencyPolicy.allowsReminder(on: monday, given: [], calendar: calendar))
        #expect(!ReminderFrequencyPolicy.allowsReminder(
            on: monday,
            given: [monday],
            calendar: calendar
        ))
    }

    @Test("Three in a rolling seven days, and the fourth is refused")
    func capAllowsThreePerRollingWeek() {
        let calendar = HistoryStatsService.isoGermanCalendar()
        let taken = ["2026-06-01", "2026-06-03", "2026-06-05"].map { Fixture.day($0) }

        #expect(!ReminderFrequencyPolicy.allowsReminder(
            on: Fixture.day("2026-06-07"),
            given: taken,
            calendar: calendar
        ))
        // The Monday has fallen out of the window by the 8th, so the fourth day
        // is admitted again — the cap bounds the rate, it does not run out.
        #expect(ReminderFrequencyPolicy.allowsReminder(
            on: Fixture.day("2026-06-08"),
            given: taken,
            calendar: calendar
        ))
    }

    @Test("A daily plan is filtered down to three reminders a week")
    func capThinsADailyPlan() {
        let calendar = HistoryStatsService.isoGermanCalendar()
        let everyDay = (0..<14).map { Fixture.day("2026-06-01", plus: $0) }

        let admitted = ReminderFrequencyPolicy.admissibleDays(
            from: everyDay,
            alreadyReminded: [],
            calendar: calendar
        )

        // Six over a fortnight, earliest first. Never four inside any seven-day
        // window — asserted over every window rather than over the answer's
        // shape, because the shape is what the implementation chose and the
        // window is what the guardrail promises.
        #expect(admitted.count == 6)
        for start in everyDay {
            guard let end = calendar.date(
                byAdding: .day,
                value: ReminderFrequencyPolicy.rollingWindowDays - 1,
                to: start
            ) else { continue }
            let inWindow = admitted.filter { $0 >= start && $0 <= end }
            #expect(inWindow.count <= ReminderFrequencyPolicy.maxRemindersPerRollingWindow)
        }
    }

    @Test("Days already reminded are what the cap is measured against")
    func capCountsThePastLedger() {
        let calendar = HistoryStatsService.isoGermanCalendar()
        let past = ["2026-06-01", "2026-06-02", "2026-06-03"].map { Fixture.day($0) }

        let admitted = ReminderFrequencyPolicy.admissibleDays(
            from: [Fixture.day("2026-06-04"), Fixture.day("2026-06-09")],
            alreadyReminded: past,
            calendar: calendar
        )

        // The 4th is inside the window the three past days fill; the 9th is not.
        #expect(admitted == [Fixture.day("2026-06-09")])
    }

    // MARK: - Which days get a reminder

    @Test("A planned Tuesday earns exactly one reminder, that Tuesday morning")
    func weekdayPlanRemindsOnThePlannedDay() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let routine = Fixture.makeRoutine(
            named: "Upper Body",
            in: context,
            type: .weekdays,
            weekdays: [2]
        )

        // Monday lunchtime.
        let reference = Fixture.moment("2026-06-01", hour: 12)
        let reminders = WorkoutReminderPlanner.reminders(
            routines: [routine],
            lastCompleted: [:],
            alreadyReminded: [],
            referenceDate: reference
        )

        // Two Tuesdays fall inside the fortnight window, and both are admitted —
        // "exactly one that Tuesday" is about the day, not about the window.
        // (The Wednesdays after them carry speculative missed-session nudges;
        // `ReEngagementNudgeTests` covers those.)
        #expect(reminders.filter { $0.kind == .plannedSession }.map(\.day)
            == [Fixture.day("2026-06-02"), Fixture.day("2026-06-09")])
        #expect(reminders.filter { $0.day == Fixture.day("2026-06-02") }.count == 1)

        let calendar = HistoryStatsService.isoGermanCalendar()
        let first = try #require(reminders.first)
        #expect(calendar.component(.hour, from: first.fireDate)
            == WorkoutReminderPlanner.reminderHour)
        // One planned routine that day, so the copy names it.
        #expect(first.routineName == "Upper Body")
    }

    @Test("A cadence is reminded on the day the app's own next-due rule names")
    func cadencePlanAgreesWithNextDue() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let routine = Fixture.makeRoutine(
            named: "Full Body",
            in: context,
            type: .everyNDays,
            intervalDays: 3,
            startDate: Fixture.day("2026-05-20")
        )
        let schedule = try #require(routine.schedule)
        // A completion after the reference date, which is what rolls the anchor
        // (docs/workout-planning.md, "Reference date").
        let lastCompleted = Fixture.day("2026-05-31")
        let reference = Fixture.moment("2026-06-01", hour: 12)

        let reminders = WorkoutReminderPlanner.reminders(
            routines: [routine],
            lastCompleted: [routine.id: lastCompleted],
            alreadyReminded: [],
            referenceDate: reference
        )

        // The Verlauf tab's and the routine card's own answer, from the other
        // side of `WorkoutPlanningService`. The reminder is not allowed to have
        // its own opinion about which day is planned.
        let nextDue = try #require(WorkoutPlanningService.nextDue(
            for: schedule,
            lastCompleted: lastCompleted,
            referenceDate: reference
        ))
        #expect(reminders.first { $0.kind == .plannedSession }?.day == HistoryStatsService.isoGermanCalendar()
            .startOfDay(for: nextDue))
    }

    @Test("A paused plan and an unplanned routine are both silent")
    func pausedAndUnplannedRoutinesEarnNothing() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let paused = Fixture.makeRoutine(
            named: "Paused",
            in: context,
            type: .weekdays,
            weekdays: [1, 2, 3, 4, 5, 6, 7]
        )
        try #require(paused.schedule).isActive = false
        let unplanned = Routine(name: "Unplanned")
        context.insert(unplanned)

        let reminders = WorkoutReminderPlanner.reminders(
            routines: [paused, unplanned],
            lastCompleted: [:],
            alreadyReminded: [],
            referenceDate: Fixture.moment("2026-06-01", hour: 12)
        )

        #expect(reminders.isEmpty)
    }

    @Test("Two routines on one day still produce one reminder, and it names neither")
    func twoRoutinesOnOneDayShareOneReminder() {
        let context = ModelContext(InMemoryModelContainer.make())
        let push = Fixture.makeRoutine(named: "Push", in: context, type: .weekdays, weekdays: [2])
        let pull = Fixture.makeRoutine(named: "Pull", in: context, type: .weekdays, weekdays: [2])

        let reminders = WorkoutReminderPlanner.reminders(
            routines: [push, pull],
            lastCompleted: [:],
            alreadyReminded: [],
            referenceDate: Fixture.moment("2026-06-01", hour: 12)
        )

        let tuesday = reminders.filter { $0.day == Fixture.day("2026-06-02") }
        #expect(tuesday.count == 1)
        #expect(tuesday.first?.routineName == nil)
    }

    @Test("A morning already past is not reminded about, and costs no allowance")
    func todaysReminderIsSkippedOnceItsHourHasPassed() {
        let context = ModelContext(InMemoryModelContainer.make())
        let routine = Fixture.makeRoutine(
            named: "Legs",
            in: context,
            type: .weekdays,
            weekdays: [1, 2]
        )

        // Monday afternoon: Monday's 08:00 is gone, Tuesday's is not.
        let reminders = WorkoutReminderPlanner.reminders(
            routines: [routine],
            lastCompleted: [:],
            alreadyReminded: [],
            referenceDate: Fixture.moment("2026-06-01", hour: 15)
        )

        #expect(!reminders.map(\.day).contains(Fixture.day("2026-06-01")))
        #expect(reminders.first?.day == Fixture.day("2026-06-02"))
    }

    // MARK: - The scheduler

    @Test("An authorized user with a plan gets one pending request per planned day, plus its nudge")
    func schedulerWritesOneRequestPerPlannedDay() async {
        let harness = Fixture.makeHarness(referenceDate: Fixture.moment("2026-06-01", hour: 12))
        harness.center.status = .authorized
        Fixture.makeRoutine(
            named: "Upper Body",
            in: harness.context,
            type: .weekdays,
            weekdays: [2]
        )

        await harness.scheduler.refreshReminders()

        #expect(harness.center.pendingIdentifiers == [
            "workoutReminder.missed.2026-06-03",
            "workoutReminder.missed.2026-06-10",
            "workoutReminder.planned.2026-06-02",
            "workoutReminder.planned.2026-06-09"
        ])
        #expect(harness.center.pendingTriggerComponents.first?.hour
            == WorkoutReminderPlanner.reminderHour)
        // The ledger records the days, so the cap can be measured across launches.
        #expect(harness.record.remindedDays.count == 4)
        // And nothing here ever asks for permission.
        #expect(harness.center.authorizationRequestCount == 0)
    }

    @Test("A refresh is idempotent — running it twice leaves one request per day")
    func schedulerRefreshIsIdempotent() async {
        let harness = Fixture.makeHarness(referenceDate: Fixture.moment("2026-06-01", hour: 12))
        harness.center.status = .authorized
        Fixture.makeRoutine(named: "Upper Body", in: harness.context, type: .weekdays, weekdays: [2])

        await harness.scheduler.refreshReminders()
        await harness.scheduler.refreshReminders()

        #expect(harness.center.pendingIdentifiers == [
            "workoutReminder.missed.2026-06-03",
            "workoutReminder.missed.2026-06-10",
            "workoutReminder.planned.2026-06-02",
            "workoutReminder.planned.2026-06-09"
        ])
    }

    @Test("Overlapping refreshes neither double-schedule nor corrupt the ledger")
    func concurrentRefreshesAreSerialized() async {
        let harness = Fixture.makeHarness(referenceDate: Fixture.moment("2026-06-01", hour: 12))
        harness.center.status = .authorized
        Fixture.makeRoutine(named: "Upper Body", in: harness.context, type: .weekdays, weekdays: [2])

        // Six unrelated triggers can fire this, each in its own `Task`. Two
        // passes that interleave would have the second's cancellation land after
        // the first had already added requests, and both would write a ledger
        // describing neither.
        // `Task { @MainActor in … }` rather than `async let`, which would make
        // the child task nonisolated and refuse to carry the main-actor harness.
        let first = Task { @MainActor in await harness.scheduler.refreshReminders() }
        let second = Task { @MainActor in await harness.scheduler.refreshReminders() }
        await first.value
        await second.value

        #expect(harness.center.pending.count == 4)
        #expect(harness.record.remindedDays.count == 4)
    }

    @Test("Nothing is scheduled without authorization")
    func schedulerIsSilentWithoutAuthorization() async {
        let harness = Fixture.makeHarness(referenceDate: Fixture.moment("2026-06-01", hour: 12))
        harness.center.status = .notDetermined
        Fixture.makeRoutine(named: "Upper Body", in: harness.context, type: .weekdays, weekdays: [2])

        await harness.scheduler.refreshReminders()

        #expect(harness.center.pending.isEmpty)
        // The scheduler must never spend the user's one irreversible answer.
        #expect(harness.center.authorizationRequestCount == 0)
    }

    @Test("A running workout withdraws every pending reminder")
    func schedulerWithdrawsRemindersDuringAWorkout() async {
        let harness = Fixture.makeHarness(referenceDate: Fixture.moment("2026-06-01", hour: 12))
        harness.center.status = .authorized
        Fixture.makeRoutine(named: "Upper Body", in: harness.context, type: .weekdays, weekdays: [2])

        await harness.scheduler.refreshReminders()
        #expect(!harness.center.pending.isEmpty)

        harness.activeWorkout.setWorkoutActive(true)
        await harness.scheduler.refreshReminders()
        #expect(harness.center.pending.isEmpty)

        // Suspended, not consumed: ending the workout puts back what is due.
        harness.activeWorkout.setWorkoutActive(false)
        await harness.scheduler.refreshReminders()
        #expect(harness.center.pending.count == 4)
    }

    @Test("This morning's reminder still counts against the rest of its week")
    func schedulerCountsAlreadyFiredRemindersAgainstTheCap() async {
        // Monday afternoon. The user has been reminded on Saturday, Sunday and
        // this morning — three inside the window — and trains every day.
        let harness = Fixture.makeHarness(referenceDate: Fixture.moment("2026-06-01", hour: 15))
        harness.center.status = .authorized
        harness.record.setRemindedDays(
            ["2026-05-30", "2026-05-31", "2026-06-01"].map { Fixture.day($0) }
        )
        Fixture.makeRoutine(
            named: "Daily",
            in: harness.context,
            type: .weekdays,
            weekdays: [1, 2, 3, 4, 5, 6, 7]
        )

        await harness.scheduler.refreshReminders()

        // The next admissible morning is the Saturday — the first day whose
        // backward window has room. Splitting the ledger on the *day* rather
        // than on the fire moment would drop this morning's reminder and let
        // Tuesday through, which is a fourth notification in seven days.
        #expect(harness.center.pendingIdentifiers.first == "workoutReminder.planned.2026-06-06")
    }

    @Test("A request the system refuses does not spend the day's allowance")
    func schedulerDoesNotRecordAFailedRequest() async {
        let harness = Fixture.makeHarness(referenceDate: Fixture.moment("2026-06-01", hour: 12))
        harness.center.status = .authorized
        harness.center.addError = CocoaError(.fileNoSuchFile)
        Fixture.makeRoutine(named: "Upper Body", in: harness.context, type: .weekdays, weekdays: [2])

        await harness.scheduler.refreshReminders()

        #expect(harness.center.pending.isEmpty)
        #expect(harness.record.remindedDays.isEmpty)
    }

    // MARK: - The permission seam

    @Test("The offer is raised on a fresh install and asks the system for nothing")
    func offerIsRaisedBeforeAnySystemPrompt() async {
        let harness = Fixture.makeHarness()
        harness.center.status = .notDetermined

        await harness.optIn.presentIfDue()

        #expect(harness.optIn.isPresenting)
        #expect(harness.center.authorizationRequestCount == 0)
    }

    @Test("Declining costs no permission, and the offer can be made again later")
    func decliningSpendsNoPermission() async {
        let declinedAt = Fixture.moment("2026-06-01", hour: 12)
        var now = declinedAt
        let harness = Fixture.makeHarness(optInNow: { now })
        harness.center.status = .notDetermined

        await harness.optIn.presentIfDue()
        harness.optIn.decline()

        #expect(!harness.optIn.isPresenting)
        // The whole point of the pre-prompt: the one irreversible ask is intact.
        #expect(harness.center.authorizationRequestCount == 0)
        #expect(harness.center.status == .notDetermined)

        // The next launch, still inside the cooldown.
        now = Fixture.moment("2026-06-10", hour: 12)
        await harness.optIn.presentIfDue()
        #expect(!harness.optIn.isPresenting)

        // And after it.
        now = Fixture.moment("2026-06-16", hour: 12)
        await harness.optIn.presentIfDue()
        #expect(harness.optIn.isPresenting)
    }

    @Test("A second decline is the last — the app stops asking")
    func theOfferIsMadeAtMostTwice() async {
        var now = Fixture.moment("2026-06-01", hour: 12)
        let harness = Fixture.makeHarness(optInNow: { now })
        harness.center.status = .notDetermined

        await harness.optIn.presentIfDue()
        harness.optIn.decline()

        now = Fixture.moment("2026-06-16", hour: 12)
        await harness.optIn.presentIfDue()
        harness.optIn.decline()

        now = Fixture.moment("2026-08-01", hour: 12)
        await harness.optIn.presentIfDue()

        #expect(!harness.optIn.isPresenting)
        #expect(harness.record.reminderOfferCount == WorkoutReminderOptInViewModel.maxOffers)
        #expect(harness.center.authorizationRequestCount == 0)
    }

    @Test("A user the rest timer already got permission from is never offered it")
    func anAlreadyAuthorizedUserIsNotAsked() async {
        let harness = Fixture.makeHarness()
        // What `UserNotificationRestTimerScheduler` leaves behind when it asks
        // lazily, mid-workout — a path this feature deliberately does not touch.
        harness.center.status = .authorized

        await harness.optIn.presentIfDue()

        #expect(!harness.optIn.isPresenting)
        #expect(harness.center.authorizationRequestCount == 0)
    }

    @Test("A user who already denied the system prompt is not asked again either")
    func aDeniedUserIsNotAsked() async {
        let harness = Fixture.makeHarness()
        harness.center.status = .denied

        await harness.optIn.presentIfDue()

        #expect(!harness.optIn.isPresenting)
    }

    @Test("A yes raises the system prompt exactly once and starts the reminders")
    func acceptingRaisesTheSystemPromptOnce() async {
        let harness = Fixture.makeHarness(referenceDate: Fixture.moment("2026-06-01", hour: 12))
        harness.center.status = .notDetermined
        harness.center.grantsAuthorization = true
        Fixture.makeRoutine(named: "Upper Body", in: harness.context, type: .weekdays, weekdays: [2])

        await harness.optIn.presentIfDue()
        await harness.optIn.accept()

        #expect(harness.center.authorizationRequestCount == 1)
        #expect(!harness.optIn.isPresenting)
        #expect(harness.record.hasAcceptedReminderOffer)
        // The yes is what makes reminders start working, in the same turn.
        #expect(harness.center.pending.count == 4)
    }

    @Test("A yes the system refuses records the answer and schedules nothing")
    func acceptingIntoASystemDenialSchedulesNothing() async {
        let harness = Fixture.makeHarness(referenceDate: Fixture.moment("2026-06-01", hour: 12))
        harness.center.status = .notDetermined
        harness.center.grantsAuthorization = false
        Fixture.makeRoutine(named: "Upper Body", in: harness.context, type: .weekdays, weekdays: [2])

        await harness.optIn.presentIfDue()
        await harness.optIn.accept()

        #expect(harness.center.pending.isEmpty)
        // Answered, so it is never offered again — the system's no is final and
        // an in-app screen cannot undo it.
        #expect(harness.record.hasAcceptedReminderOffer)
        await harness.optIn.presentIfDue()
        #expect(!harness.optIn.isPresenting)
    }

    @Test("The offer is not raised inside a workout, and is not spent by being held back")
    func theOfferWaitsOutAnActiveWorkout() async {
        let harness = Fixture.makeHarness()
        harness.center.status = .notDetermined
        harness.activeWorkout.setWorkoutActive(true)

        await harness.optIn.presentIfDue()
        #expect(!harness.optIn.isPresenting)
        #expect(harness.record.reminderOfferCount == 0)

        harness.activeWorkout.setWorkoutActive(false)
        await harness.optIn.presentIfDue()
        #expect(harness.optIn.isPresenting)
    }

    @Test("A dismissal this type did not initiate is read as a decline, once")
    func aStrayDismissalRecordsOneDecline() async {
        let harness = Fixture.makeHarness()
        harness.center.status = .notDetermined

        await harness.optIn.presentIfDue()
        harness.optIn.offerWasDismissed()
        // SwiftUI writes the binding back after the flag is already down.
        harness.optIn.offerWasDismissed()

        #expect(harness.record.reminderOfferCount == 1)
    }
}
