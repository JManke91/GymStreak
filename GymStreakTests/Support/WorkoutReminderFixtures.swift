//
//  WorkoutReminderFixtures.swift
//  GymStreakTests
//
//  Shared harness, routines and dates for the reminder suites
//  (`WorkoutReminderTests`, `ReEngagementNudgeTests`).
//  See docs/workout-reminders.md.
//

import Foundation
import SwiftData
@testable import GymStreak

@MainActor
enum WorkoutReminderFixtures {

    // MARK: - Harness

    struct Harness {
        let context: ModelContext
        let center: FakeWorkoutReminderNotificationCenter
        let record: WorkoutReminderStore
        let activeWorkout: ActiveWorkoutRegistry
        let scheduler: UserNotificationWorkoutReminderScheduler
        let optIn: WorkoutReminderOptInViewModel
    }

    /// The real store over a throwaway suite, because half the reminder
    /// assertions are about what was written down — the half a double would
    /// assert away.
    static func makeHarness(
        referenceDate: Date = Date(),
        optInNow: @escaping () -> Date = Date.init
    ) -> Harness {
        makeHarness(now: { referenceDate }, optInNow: optInNow)
    }

    /// A harness whose scheduler clock the test can move.
    static func makeHarness(
        now: @escaping () -> Date,
        optInNow: @escaping () -> Date = Date.init
    ) -> Harness {
        let suiteName = "test.reminders.\(UUID().uuidString)"
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!

        let context = ModelContext(InMemoryModelContainer.make())
        let center = FakeWorkoutReminderNotificationCenter()
        let record = WorkoutReminderStore(defaults: defaults)
        let activeWorkout = ActiveWorkoutRegistry()
        let scheduler = UserNotificationWorkoutReminderScheduler(
            notificationCenter: center,
            routineRepository: SwiftDataRoutineRepository(modelContext: context),
            workoutSessionRepository: SwiftDataWorkoutSessionRepository(modelContext: context),
            record: record,
            activeWorkout: activeWorkout,
            now: now
        )
        let optIn = WorkoutReminderOptInViewModel(
            record: record,
            // The **real** Domain gateway over the faked centre, rather than a
            // second double: the projection is thin enough that a double would
            // only be able to drift from it.
            permission: UserNotificationReminderPermission(notificationCenter: center),
            scheduler: scheduler,
            activeWorkout: activeWorkout,
            now: optInNow
        )
        return Harness(
            context: context,
            center: center,
            record: record,
            activeWorkout: activeWorkout,
            scheduler: scheduler,
            optIn: optIn
        )
    }

    // MARK: - Models

    /// A routine with an active plan. `createdAt` defaults to the real clock,
    /// which is later than every date these tests use — pass `createdAt` when a
    /// test depends on a planned day in the past counting as planned.
    @discardableResult
    static func makeRoutine(
        named name: String,
        in context: ModelContext,
        type: RoutineScheduleType,
        intervalDays: Int = 3,
        weekdays: Set<Int> = [],
        startDate: Date = Date(),
        createdAt: Date? = nil
    ) -> Routine {
        let routine = Routine(name: name)
        context.insert(routine)
        let schedule = RoutineSchedule(
            type: type,
            intervalDays: intervalDays,
            weekdays: weekdays,
            startDate: startDate
        )
        schedule.isActive = true
        if let createdAt { schedule.createdAt = createdAt }
        schedule.routine = routine
        context.insert(schedule)
        return routine
    }

    /// A finished workout, the thing every nudge is withdrawn by.
    static func completeWorkout(at start: Date, routine: Routine? = nil, in context: ModelContext) {
        let session = WorkoutSession(routine: routine)
        session.startTime = start
        session.endTime = start.addingTimeInterval(3600)
        context.insert(session)
    }

    // MARK: - Dates

    /// Start of the given `yyyy-MM-dd` day, in the app's own ISO calendar — the
    /// one every planning helper uses, so the tests cannot disagree with the
    /// code about where a day begins.
    static func day(_ iso: String, plus days: Int = 0) -> Date {
        let calendar = HistoryStatsService.isoGermanCalendar()
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        let start = calendar.startOfDay(for: calendar.date(from: components) ?? Date())
        return calendar.date(byAdding: .day, value: days, to: start) ?? start
    }

    static func moment(_ iso: String, hour: Int) -> Date {
        let calendar = HistoryStatsService.isoGermanCalendar()
        return calendar.date(
            bySettingHour: hour, minute: 0, second: 0, of: day(iso)
        ) ?? day(iso)
    }
}
