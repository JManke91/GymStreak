//
//  HistoryStatsService.swift
//  GymStreak
//

import Foundation
import SwiftData

/// Aggregated statistics used by the History redesign (WeekHero, calendar month totals, streaks).
/// All methods are synchronous and operate on already-fetched WorkoutSession arrays to keep the
/// View layer simple and avoid re-hitting SwiftData on every render.
struct HistoryStatsService {

    // MARK: - Week Stats

    struct WeekStats: Sendable {
        let completedCount: Int          // finished workouts in the current week (Mon–Sun)
        let goal: Int                    // target workouts per week
        let weekVolume: Double           // summed volume for the current week, kg
        let volumeTrendPct: Double?      // % change vs previous week (nil if no prev data)
        let prCount: Int                 // new PRs logged this week
        let streakWeeks: Int             // consecutive weeks ending with current or prior week
    }

    /// Computes the WeekHero stats for the week containing `referenceDate` (typically "now").
    /// `goal` is the dynamic weekly training goal derived from the user's planned routines
    /// (see `WorkoutPlanningService`); 0 means nothing is planned yet.
    static func weekStats(
        sessions: [WorkoutSession],
        prExerciseCountBySession: [UUID: Int],
        goal: Int,
        referenceDate: Date = Date()
    ) -> WeekStats {
        let calendar = isoGermanCalendar()
        let weekRange = weekInterval(containing: referenceDate, calendar: calendar)
        let prevRange = weekInterval(
            containing: calendar.date(byAdding: .day, value: -7, to: referenceDate) ?? referenceDate,
            calendar: calendar
        )

        let thisWeekSessions = sessions.filter { session in
            session.endTime != nil && weekRange.contains(session.startTime)
        }
        let prevWeekSessions = sessions.filter { session in
            session.endTime != nil && prevRange.contains(session.startTime)
        }

        let weekVolume = thisWeekSessions.reduce(0.0) { $0 + $1.totalVolume }
        let prevVolume = prevWeekSessions.reduce(0.0) { $0 + $1.totalVolume }
        let trend: Double? = prevVolume > 0 ? ((weekVolume - prevVolume) / prevVolume) * 100 : nil

        let prCount = thisWeekSessions.reduce(0) { total, session in
            total + (prExerciseCountBySession[session.id] ?? 0)
        }

        let streak = streakWeeks(sessions: sessions, referenceDate: referenceDate, calendar: calendar)

        return WeekStats(
            completedCount: thisWeekSessions.count,
            goal: goal,
            weekVolume: weekVolume,
            volumeTrendPct: trend,
            prCount: prCount,
            streakWeeks: streak
        )
    }

    // MARK: - Week-day strip

    struct WeekDayStatus: Identifiable, Sendable {
        /// The day itself, so a rebuilt strip updates its cells instead of replacing them.
        var id: Date { date }
        let date: Date
        let weekday: Int     // 1 = Monday ... 7 = Sunday
        let label: String    // "Mo", "Di", ...
        let isToday: Bool
        let isFuture: Bool
        let hasWorkout: Bool
        let isPlanned: Bool   // a routine is scheduled for this day (see WorkoutPlanningService)
    }

    /// Monday-first weekday strip for the week containing `referenceDate`.
    /// `plannedDates` are start-of-day dates that carry a scheduled session.
    static func weekDayStatuses(
        sessions: [WorkoutSession],
        plannedDates: Set<Date> = [],
        referenceDate: Date = Date()
    ) -> [WeekDayStatus] {
        let calendar = isoGermanCalendar()
        let today = calendar.startOfDay(for: referenceDate)
        let weekRange = weekInterval(containing: referenceDate, calendar: calendar)

        // Map of yyyy-MM-dd → has workout
        let workoutDays = Set(
            sessions
                .filter { $0.endTime != nil && weekRange.contains($0.startTime) }
                .map { calendar.startOfDay(for: $0.startTime) }
        )

        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: weekRange.start) ?? weekRange.start
            let startOfDate = calendar.startOfDay(for: date)
            return WeekDayStatus(
                date: startOfDate,
                weekday: offset + 1,
                label: weekdayLabel(for: startOfDate),
                isToday: startOfDate == today,
                isFuture: startOfDate > today,
                hasWorkout: workoutDays.contains(startOfDate),
                isPlanned: plannedDates.contains(startOfDate)
            )
        }
    }

    // MARK: - Month grouping

    // `groupByMonth` and `monthStats` lived here until 2026-07-26. Both walked every session's
    // `totalVolume` and were called from inside `body`; `HistorySnapshotBuilder` now derives the
    // month sections and the calendar's month totals from the single pass that builds the cards, so
    // both were dead and are gone rather than left as a tempting shortcut back into a view body.

    // MARK: - Streak

    /// Consecutive weeks ending at the current (or most-recent completed) week that contain
    /// at least one finished workout.
    static func streakWeeks(
        sessions: [WorkoutSession],
        referenceDate: Date = Date(),
        calendar: Calendar? = nil
    ) -> Int {
        let calendar = calendar ?? isoGermanCalendar()
        let finished = sessions.filter { $0.endTime != nil }
        // The week's Monday (a Date) is the identity of a week — no string key, and therefore no
        // DateFormatter per session and per loop iteration (docs/history-performance.md §2.2).
        let workoutWeeks = Set(finished.map { weekStartKey(for: $0.startTime, calendar: calendar) })

        let currentKey = weekStartKey(for: referenceDate, calendar: calendar)
        var streak = 0
        var cursor = referenceDate

        // If current week has no workout, start counting from the previous week.
        if !workoutWeeks.contains(currentKey) {
            cursor = calendar.date(byAdding: .day, value: -7, to: cursor) ?? cursor
        }

        while true {
            let key = weekStartKey(for: cursor, calendar: calendar)
            if workoutWeeks.contains(key) {
                streak += 1
                cursor = calendar.date(byAdding: .day, value: -7, to: cursor) ?? cursor
            } else {
                break
            }
        }

        return streak
    }

    // MARK: - Calendar helpers

    /// Calendar set to Monday-first, German locale — matches the app's German UI and the design.
    static func isoGermanCalendar() -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2       // Monday
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    /// DateInterval spanning the Monday → following Monday (exclusive end) of the week containing `date`.
    static func weekInterval(containing date: Date, calendar: Calendar) -> DateInterval {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        // weekday: 1=Sun, 2=Mon ... in Gregorian. firstWeekday=2 means Monday; offset back accordingly.
        let daysFromStart = ((weekday - calendar.firstWeekday) + 7) % 7
        let start = calendar.date(byAdding: .day, value: -daysFromStart, to: startOfDay) ?? startOfDay
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    /// Identity of the week containing `date`: its Monday, normalised to the start of that day.
    ///
    /// The extra `startOfDay` is not redundant. Where a DST transition happens *at* midnight
    /// (America/Havana, America/Santiago), `weekInterval` can return the same Monday at 00:00 for
    /// one weekday and at 01:00 for another, so one calendar week would yield two distinct keys and
    /// a streak would break a week early. The formatter-based `"yyyy-MM-dd"` key this replaced
    /// collapsed that hour implicitly; `startOfDay` restores the behaviour without a DateFormatter.
    private static func weekStartKey(for date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: weekInterval(containing: date, calendar: calendar).start)
    }

    // MARK: - Formatters

    // Hoisted to statics: these were allocated per session, per weekday and per month group on
    // every render of the History screen (docs/history-performance.md §2.2). Both are configured
    // with the Monday-first calendar these labels are always rendered in.

    private static let weekdayLabelStyle = Date.FormatStyle(
        date: .omitted,
        time: .omitted,
        locale: .current,
        calendar: isoGermanCalendar()
    )
    .weekday(.short)

    private static let monthLabelStyle = Date.FormatStyle(
        date: .omitted,
        time: .omitted,
        locale: .current,
        calendar: isoGermanCalendar()
    )
    .month(.wide)
    .year()

    private static func weekdayLabel(for date: Date) -> String {
        let raw = date.formatted(weekdayLabelStyle)
        // .shortWeekdaySymbols often include a trailing "."; keep first 2 alphabetic characters.
        return String(raw.filter(\.isLetter).prefix(2))
    }

    /// Localized "MMMM yyyy" label for a year/month pair. Shared by the calendar header, the
    /// month dividers and the coach entry card so they cannot drift apart.
    static func monthYearLabel(year: Int, month: Int) -> String {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        let date = isoGermanCalendar().date(from: comps) ?? Date()
        return date.formatted(monthLabelStyle)
    }

    static func monthYearLabel(for date: Date) -> String {
        date.formatted(monthLabelStyle)
    }
}
