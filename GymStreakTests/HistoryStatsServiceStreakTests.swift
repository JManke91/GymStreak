//
//  HistoryStatsServiceStreakTests.swift
//  GymStreakTests
//
//  Regression coverage for the week identity used by `HistoryStatsService.streakWeeks`.
//
//  The streak used to key weeks by a "yyyy-MM-dd" String built with a DateFormatter — one
//  formatter allocation per session and per loop iteration, a measured contributor to the
//  History screen's main-thread hang (docs/history-performance.md §2.2). The key is now the
//  week's Monday as a Date. Two dates in the same week must therefore collapse to the exact
//  same Date, which only holds if the Monday is normalised to the start of its day: in zones
//  that shift the clock *at midnight*, `weekInterval(containing:).start` can land on 00:00 for
//  one weekday of a week and 01:00 for another, and the streak would break a week early.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct HistoryStatsServiceStreakTests {

    // MARK: - Helpers

    private func calendar(timeZone identifier: String) throws -> Calendar {
        var calendar = HistoryStatsService.isoGermanCalendar()
        calendar.timeZone = try #require(TimeZone(identifier: identifier))
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int,
        calendar: Calendar
    ) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return try #require(calendar.date(from: components))
    }

    private func finishedSession(startingAt start: Date, context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(routine: nil)
        session.startTime = start
        session.endTime = start.addingTimeInterval(3_600)
        context.insert(session)
        return session
    }

    // MARK: - Midnight-DST regression

    /// Cuba shifts clocks forward at 00:00 on the second Sunday of March, so 2026-03-08 has no
    /// midnight and its start-of-day is 01:00. A workout earlier that same week (Tuesday) and a
    /// reference date on that Sunday must still resolve to one week, i.e. streak == 1.
    ///
    /// Before the fix this returned 0: the session keyed the week as Monday 00:00 and the
    /// reference date keyed it as Monday 01:00, so the lookup missed and the loop stepped back
    /// into an empty week.
    @Test
    func streakCountsCurrentWeekWhenReferenceDateFallsOnAMidnightDSTTransition() throws {
        let calendar = try calendar(timeZone: "America/Havana")
        let context = ModelContext(InMemoryModelContainer.make())

        let transitionDay = try date(2026, 3, 8, hour: 12, calendar: calendar)
        // Guard the premise rather than trusting tzdata silently: if a future tzdata release
        // removes Cuba's midnight transition this test would pass without exercising the path.
        // `#require` so it stops here rather than continuing to a vacuous pass.
        try #require(
            calendar.component(.hour, from: calendar.startOfDay(for: transitionDay)) == 1,
            "America/Havana no longer skips midnight on 2026-03-08 — pick another zone/date."
        )

        let workoutDay = try date(2026, 3, 3, hour: 9, calendar: calendar)
        let session = finishedSession(startingAt: workoutDay, context: context)

        let streak = HistoryStatsService.streakWeeks(
            sessions: [session],
            referenceDate: transitionDay,
            calendar: calendar
        )

        #expect(streak == 1)
    }

    /// The mirror case: the workout itself falls on the midnight-transition day and the reference
    /// date is an ordinary weekday of the same week.
    @Test
    func streakCountsWorkoutRecordedOnAMidnightDSTTransitionDay() throws {
        let calendar = try calendar(timeZone: "America/Havana")
        let context = ModelContext(InMemoryModelContainer.make())

        let transitionDay = try date(2026, 3, 8, hour: 10, calendar: calendar)
        let session = finishedSession(startingAt: transitionDay, context: context)

        let streak = HistoryStatsService.streakWeeks(
            sessions: [session],
            // Tuesday of the same Monday-first week as Sunday 2026-03-08.
            referenceDate: try date(2026, 3, 3, hour: 20, calendar: calendar),
            calendar: calendar
        )

        #expect(streak == 1)
    }

    // MARK: - Ordinary behaviour (guards the rewrite itself)

    /// Consecutive weeks accumulate, and a gap terminates the streak — verified in a zone with a
    /// 02:00 DST transition, where the old String key and the new Date key agree.
    @Test
    func streakCountsConsecutiveWeeksAndStopsAtAGap() throws {
        let calendar = try calendar(timeZone: "Europe/Berlin")
        let context = ModelContext(InMemoryModelContainer.make())

        // Reference: Wednesday 2026-04-15. Weeks: 13.4.–19.4., 6.4.–12.4., 30.3.–5.4. (spans the
        // 2026-03-29 02:00 DST change), then a deliberately skipped week, then 16.3.–22.3.
        let referenceDate = try date(2026, 4, 15, hour: 18, calendar: calendar)
        let sessions = try [
            date(2026, 4, 15, hour: 7, calendar: calendar),
            date(2026, 4, 8, hour: 19, calendar: calendar),
            date(2026, 3, 30, hour: 6, calendar: calendar),
            date(2026, 3, 17, hour: 6, calendar: calendar)   // after the gap — must not count
        ].map { finishedSession(startingAt: $0, context: context) }

        let streak = HistoryStatsService.streakWeeks(
            sessions: sessions,
            referenceDate: referenceDate,
            calendar: calendar
        )

        #expect(streak == 3)
    }

    /// An unfinished session (no `endTime`) does not sustain a streak.
    @Test
    func streakIgnoresUnfinishedSessions() throws {
        let calendar = try calendar(timeZone: "Europe/Berlin")
        let context = ModelContext(InMemoryModelContainer.make())

        let open = WorkoutSession(routine: nil)
        open.startTime = try date(2026, 4, 14, hour: 9, calendar: calendar)
        context.insert(open)

        let streak = HistoryStatsService.streakWeeks(
            sessions: [open],
            referenceDate: try date(2026, 4, 15, hour: 18, calendar: calendar),
            calendar: calendar
        )

        #expect(streak == 0)
    }
}
