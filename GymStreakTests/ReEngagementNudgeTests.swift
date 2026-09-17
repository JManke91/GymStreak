//
//  ReEngagementNudgeTests.swift
//  GymStreakTests
//
//  Ticket 04: the missed-session nudge and its dormancy fallback
//  (docs/workout-reminders.md, "Re-engagement nudges").
//
//  What carries the ticket: **one nudge, not a stream** — a missed Tuesday earns
//  one, a lapse earns at most one a week; **never to someone who trained** — a
//  completed workout withdraws what is pending; and **one cap** — the nudges
//  join ticket 03's `ReminderFrequencyPolicy` rather than adding their own, and
//  never displace a reminder about a session the user actually planned.
//  Withdrawal through the real scheduler lives in `ReEngagementNudgeSchedulerTests`.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct ReEngagementNudgeTests {

    private typealias Fixture = WorkoutReminderFixtures

    // MARK: - Missed planned session

    @Test("A planned Tuesday with nothing logged earns one nudge, the next morning")
    func missedTuesdayEarnsOneNudge() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        Fixture.makeRoutine(
            named: "Upper Body",
            in: context,
            type: .weekdays,
            weekdays: [2],
            createdAt: Fixture.day("2026-05-01")
        )

        // Wednesday, before the 08:00 fire time. Last trained the Tuesday before.
        let reminders = WorkoutReminderPlanner.reminders(
            routines: context.routines,
            lastCompleted: [:],
            lastWorkoutDate: Fixture.moment("2026-05-26", hour: 18),
            alreadyReminded: [],
            referenceDate: Fixture.moment("2026-06-03", hour: 7)
        )

        // Exactly one nudge for the missed 2nd, and nothing else that week — the
        // next nudge in the window belongs to the *next* Tuesday.
        let nudgesThatWeek = reminders.filter {
            $0.kind == .missedSession && $0.day < Fixture.day("2026-06-09")
        }
        #expect(nudgesThatWeek.map(\.day) == [Fixture.day("2026-06-03")])
        #expect(nudgesThatWeek.first?.routineName == "Upper Body")
        #expect(reminders.filter { $0.day == Fixture.day("2026-06-03") }.count == 1)
    }

    @Test("A session logged on the planned day — any routine — means nothing was missed")
    func trainingOnThePlannedDayMeansNoNudge() {
        let context = ModelContext(InMemoryModelContainer.make())
        Fixture.makeRoutine(
            named: "Upper Body",
            in: context,
            type: .weekdays,
            weekdays: [2],
            createdAt: Fixture.day("2026-05-01")
        )

        let reminders = WorkoutReminderPlanner.reminders(
            routines: context.routines,
            lastCompleted: [:],
            lastWorkoutDate: Fixture.moment("2026-06-02", hour: 18),
            alreadyReminded: [],
            referenceDate: Fixture.moment("2026-06-03", hour: 7)
        )

        #expect(!reminders.contains { $0.day == Fixture.day("2026-06-03") })
    }

    @Test("A plan set up today has not been missed yesterday")
    func aPlanCreatedTodayMissedNothingYesterday() {
        let context = ModelContext(InMemoryModelContainer.make())
        // A Monday plan, created on Tuesday morning.
        Fixture.makeRoutine(
            named: "Legs",
            in: context,
            type: .weekdays,
            weekdays: [1],
            createdAt: Fixture.moment("2026-06-02", hour: 6)
        )

        let reminders = WorkoutReminderPlanner.reminders(
            routines: context.routines,
            lastCompleted: [:],
            alreadyReminded: [],
            referenceDate: Fixture.moment("2026-06-02", hour: 7)
        )

        #expect(!reminders.contains { $0.day == Fixture.day("2026-06-02") })
    }

    // MARK: - Dormancy

    @Test("No plan and no workout since install: a nudge after the threshold, one a week")
    func dormancyNudgesAUserWithNoPlan() {
        let context = ModelContext(InMemoryModelContainer.make())
        // The seeded starter routine: present, but unplanned.
        context.insert(Routine(name: "Starter"))
        let installed = Fixture.moment("2026-06-01", hour: 9)

        let reminders = WorkoutReminderPlanner.reminders(
            routines: context.routines,
            lastCompleted: [:],
            firstSeenAt: installed,
            alreadyReminded: [],
            referenceDate: installed
        )

        #expect(reminders.allSatisfy { $0.kind == .dormancy })
        #expect(reminders.map(\.day) == [
            Fixture.day("2026-06-01", plus: ReEngagementNudgePlanner.dormancyThresholdDays),
            Fixture.day(
                "2026-06-01",
                plus: ReEngagementNudgePlanner.dormancyThresholdDays
                    + ReEngagementNudgePlanner.dormancySpacingDays
            )
        ])
        // Never two inside a rolling week.
        for (earlier, later) in zip(reminders, reminders.dropFirst()) {
            let gap = HistoryStatsService.isoGermanCalendar()
                .dateComponents([.day], from: earlier.day, to: later.day).day ?? 0
            #expect(gap >= 7)
        }
    }

    @Test("No plan and recent activity: nothing inside the threshold")
    func recentActivityEarnsNothingYet() {
        let context = ModelContext(InMemoryModelContainer.make())
        context.insert(Routine(name: "Starter"))
        let trained = Fixture.moment("2026-06-01", hour: 18)

        let reminders = WorkoutReminderPlanner.reminders(
            routines: context.routines,
            lastCompleted: [:],
            lastWorkoutDate: trained,
            firstSeenAt: Fixture.day("2026-01-01"),
            alreadyReminded: [],
            referenceDate: Fixture.moment("2026-06-02", hour: 12)
        )

        let threshold = Fixture.day("2026-06-01", plus: ReEngagementNudgePlanner.dormancyThresholdDays)
        #expect(!reminders.contains { $0.day < threshold })
    }

    @Test("A lapse that already used its nudges stays quiet until the user trains")
    func aLongLapseGoesQuiet() {
        let context = ModelContext(InMemoryModelContainer.make())
        context.insert(Routine(name: "Starter"))

        let reminders = WorkoutReminderPlanner.reminders(
            routines: context.routines,
            lastCompleted: [:],
            lastWorkoutDate: Fixture.moment("2026-05-01", hour: 18),
            alreadyReminded: [],
            referenceDate: Fixture.moment("2026-06-01", hour: 12)
        )

        #expect(reminders.isEmpty)
    }

    @Test("A user with a plan is never sent the dormancy nudge")
    func aScheduledUserIsNeverDormant() {
        let context = ModelContext(InMemoryModelContainer.make())
        Fixture.makeRoutine(named: "Upper Body", in: context, type: .weekdays, weekdays: [2])

        let reminders = WorkoutReminderPlanner.reminders(
            routines: context.routines,
            lastCompleted: [:],
            lastWorkoutDate: Fixture.moment("2026-05-29", hour: 18),
            firstSeenAt: Fixture.day("2026-01-01"),
            alreadyReminded: [],
            referenceDate: Fixture.moment("2026-06-01", hour: 12)
        )

        #expect(!reminders.contains { $0.kind == .dormancy })
    }

    // MARK: - One cap

    @Test("A day wanted by two triggers carries one notification")
    func triggersDoNotStackOnOneDay() {
        let context = ModelContext(InMemoryModelContainer.make())
        // Tuesday and Wednesday: a missed Tuesday's nudge wants Wednesday, which
        // is already a planned day.
        Fixture.makeRoutine(
            named: "Split",
            in: context,
            type: .weekdays,
            weekdays: [2, 3],
            createdAt: Fixture.day("2026-05-01")
        )

        let reminders = WorkoutReminderPlanner.reminders(
            routines: context.routines,
            lastCompleted: [:],
            alreadyReminded: [],
            referenceDate: Fixture.moment("2026-06-01", hour: 12)
        )

        let days = reminders.map(\.day)
        #expect(Set(days).count == days.count)
        #expect(reminders.first { $0.day == Fixture.day("2026-06-03") }?.kind == .plannedSession)
    }

    @Test("Nudges fill what the cap leaves and never displace a planned reminder")
    func nudgesNeverDisplacePlannedReminders() {
        let context = ModelContext(InMemoryModelContainer.make())
        // Monday, Wednesday, Friday: three planned reminders already fill every
        // week, so the three speculative nudges between them are refused.
        Fixture.makeRoutine(
            named: "Full Body",
            in: context,
            type: .weekdays,
            weekdays: [1, 3, 5],
            createdAt: Fixture.day("2026-05-01")
        )

        let reminders = WorkoutReminderPlanner.reminders(
            routines: context.routines,
            lastCompleted: [:],
            alreadyReminded: [],
            referenceDate: Fixture.moment("2026-06-01", hour: 7)
        )

        #expect(reminders.allSatisfy { $0.kind == .plannedSession })
        #expect(reminders.count == 6)
    }

    @Test("The cap checks forward windows too, so a lower tier cannot overfill one")
    func capRefusesAnEarlierDayThatOverfillsALaterWindow() {
        let calendar = HistoryStatsService.isoGermanCalendar()
        let taken = ["2026-06-03", "2026-06-04", "2026-06-05"].map { Fixture.day($0) }

        // The window ending on the 1st is empty; the window starting on it is
        // not.
        #expect(!ReminderFrequencyPolicy.allowsReminder(
            on: Fixture.day("2026-06-01"),
            given: taken,
            calendar: calendar
        ))
    }
}

private extension ModelContext {
    var routines: [Routine] { (try? fetch(FetchDescriptor<Routine>())) ?? [] }
}
