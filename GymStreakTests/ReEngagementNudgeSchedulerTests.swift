//
//  ReEngagementNudgeSchedulerTests.swift
//  GymStreakTests
//
//  Ticket 04, through the real scheduler: a completed workout withdraws the
//  nudges that were scheduled ahead of it (docs/workout-reminders.md,
//  "Scheduled ahead, withdrawn by training").
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct ReEngagementNudgeSchedulerTests {

    private typealias Fixture = WorkoutReminderFixtures

    @Test("Completing a workout withdraws the pending missed-session nudge")
    func completingAWorkoutClearsTheMissedNudge() async {
        var now = Fixture.moment("2026-06-02", hour: 7)
        let harness = Fixture.makeHarness(now: { now })
        harness.center.status = .authorized
        let routine = Fixture.makeRoutine(
            named: "Upper Body",
            in: harness.context,
            type: .weekdays,
            weekdays: [2],
            createdAt: Fixture.day("2026-05-01")
        )

        await harness.scheduler.refreshReminders()
        #expect(harness.center.pendingIdentifiers.contains("workoutReminder.missed.2026-06-03"))

        now = Fixture.moment("2026-06-02", hour: 19)
        Fixture.completeWorkout(at: Fixture.moment("2026-06-02", hour: 18), routine: routine, in: harness.context)
        await harness.scheduler.refreshReminders()

        #expect(!harness.center.pendingIdentifiers.contains("workoutReminder.missed.2026-06-03"))
        #expect(harness.center.authorizationRequestCount == 0)
    }

    @Test("Completing a workout moves the dormancy nudge back by a whole lapse")
    func completingAWorkoutResetsDormancy() async {
        var now = Fixture.moment("2026-06-01", hour: 12)
        let harness = Fixture.makeHarness(now: { now })
        harness.center.status = .authorized

        // The first pass records the install-date stand-in.
        await harness.scheduler.refreshReminders()
        #expect(harness.center.pendingIdentifiers.first == "workoutReminder.dormancy.2026-06-05")

        now = Fixture.moment("2026-06-03", hour: 19)
        Fixture.completeWorkout(at: Fixture.moment("2026-06-03", hour: 18), in: harness.context)
        await harness.scheduler.refreshReminders()

        #expect(harness.center.pendingIdentifiers == [
            "workoutReminder.dormancy.2026-06-07",
            "workoutReminder.dormancy.2026-06-14"
        ])
        // The copy is the dormancy copy, which names no routine.
        #expect(harness.center.pendingBodies.allSatisfy {
            $0 == "notification.dormancy.body".localized
        })
    }
}
