//
//  HistoryStatsService.swift
//  GymStreak
//

import Foundation
import SwiftData

/// Aggregated statistics used by the History redesign (WeekHero, calendar month totals, streaks).
/// All methods are synchronous and operate on already-fetched WorkoutSession arrays to keep the
/// View layer simple and avoid re-hitting SwiftData on every render.
@MainActor
struct HistoryStatsService {

    // MARK: - Week Stats

    struct WeekStats {
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

    struct WeekDayStatus: Identifiable {
        let id = UUID()
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
                label: weekdayLabel(for: startOfDate, calendar: calendar),
                isToday: startOfDate == today,
                isFuture: startOfDate > today,
                hasWorkout: workoutDays.contains(startOfDate),
                isPlanned: plannedDates.contains(startOfDate)
            )
        }
    }

    // MARK: - Month grouping

    struct MonthSectionInfo {
        let year: Int
        let month: Int        // 1...12
        let label: String
        let sessions: [WorkoutSession]
        let totalVolume: Double
    }

    static func groupByMonth(sessions: [WorkoutSession]) -> [MonthSectionInfo] {
        let calendar = isoGermanCalendar()
        let grouped = Dictionary(grouping: sessions) { session -> DateComponents in
            calendar.dateComponents([.year, .month], from: session.startTime)
        }
        return grouped
            .compactMap { (key, value) -> MonthSectionInfo? in
                guard let year = key.year, let month = key.month else { return nil }
                let label = monthLabel(year: year, month: month, calendar: calendar)
                let volume = value.reduce(0.0) { $0 + $1.totalVolume }
                return MonthSectionInfo(
                    year: year,
                    month: month,
                    label: label,
                    sessions: value.sorted { $0.startTime > $1.startTime },
                    totalVolume: volume
                )
            }
            .sorted { ($0.year, $0.month) > ($1.year, $1.month) }
    }

    /// Month stats (sessions, volume) for the given year / month.
    static func monthStats(
        sessions: [WorkoutSession],
        year: Int,
        month: Int
    ) -> (sessions: Int, volume: Double) {
        let calendar = isoGermanCalendar()
        let matches = sessions.filter { session in
            let comps = calendar.dateComponents([.year, .month], from: session.startTime)
            return comps.year == year && comps.month == month && session.endTime != nil
        }
        return (matches.count, matches.reduce(0.0) { $0 + $1.totalVolume })
    }

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
        let workoutWeeks = Set(finished.map { weekKey(for: $0.startTime, calendar: calendar) })

        let currentKey = weekKey(for: referenceDate, calendar: calendar)
        var streak = 0
        var cursor = referenceDate

        // If current week has no workout, start counting from the previous week.
        if !workoutWeeks.contains(currentKey) {
            cursor = calendar.date(byAdding: .day, value: -7, to: cursor) ?? cursor
        }

        while true {
            let key = weekKey(for: cursor, calendar: calendar)
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

    private static func weekKey(for date: Date, calendar: Calendar) -> String {
        let interval = weekInterval(containing: date, calendar: calendar)
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: interval.start)
    }

    private static func weekdayLabel(for date: Date, calendar: Calendar) -> String {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.locale = Locale.current
        fmt.setLocalizedDateFormatFromTemplate("EEEEEE") // "Mo", "Di"...
        let raw = fmt.string(from: date)
        // .shortWeekdaySymbols often include a trailing "."; keep first 2 alphabetic characters.
        return String(raw.filter(\.isLetter).prefix(2))
    }

    private static func monthLabel(year: Int, month: Int, calendar: Calendar) -> String {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.locale = Locale.current
        fmt.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        let date = calendar.date(from: comps) ?? Date()
        return fmt.string(from: date)
    }
}
