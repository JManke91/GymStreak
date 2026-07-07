//
//  WorkoutPlanningService.swift
//  GymStreak
//
//  Pure scheduling logic that turns per-routine `RoutineSchedule`s + workout
//  history into (a) the dynamic weekly goal shown in the Verlauf tab and
//  (b) the "next due" date used to order routines and label cards.
//  See docs/workout-planning.md for the semantics, in particular how the
//  `.everyNDays` cadence "rolls" off the last completed session while keeping
//  the weekly goal stable within a given week.
//
//  Reuses `HistoryStatsService`'s Monday-first ISO calendar and week interval
//  so planning and history never disagree on week boundaries.
//

import Foundation

@MainActor
enum WorkoutPlanningService {

    /// The planned shape of a single week.
    struct PlannedWeek {
        /// Total number of planned sessions that land inside the week.
        let goal: Int
        /// Start-of-day dates in the week that carry at least one planned session.
        let plannedDates: Set<Date>
        /// The Mon–Sun interval these figures describe.
        let week: DateInterval
    }

    // MARK: - Weekly plan

    /// Computes the weekly goal + planned days for the week containing
    /// `referenceDate`. Planned days marked on the day-strip and the goal both
    /// follow the **live** plan (matching the "next due" shown on cards), so a
    /// day is only marked when it is genuinely completed or genuinely upcoming —
    /// today is never marked unless a session is actually due today.
    ///
    /// - Weekday plans: the goal is the (fixed) count of selected weekdays in
    ///   the week; every selected weekday is marked (past ones read as "missed").
    /// - Cadence plans: the goal is what you've already trained this week plus
    ///   the sessions still upcoming (from the live cadence). Only upcoming days
    ///   are marked as planned; completed days already render as checkmarks, and
    ///   past un-trained days are neither counted nor marked. This keeps the
    ///   denominator stable in normal use while never mislabelling today.
    static func plannedWeek(
        routines: [Routine],
        completedSessions: [WorkoutSession],
        referenceDate: Date = Date()
    ) -> PlannedWeek {
        let calendar = HistoryStatsService.isoGermanCalendar()
        let week = HistoryStatsService.weekInterval(containing: referenceDate, calendar: calendar)
        let today = calendar.startOfDay(for: referenceDate)

        var plannedDates: Set<Date> = []
        var goal = 0

        for routine in routines {
            guard let schedule = routine.schedule, schedule.isActive else { continue }

            switch schedule.type {
            case .weekdays:
                let days = schedule.weekdays
                    .sorted()
                    .compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: week.start) }
                    .filter { week.contains($0) }
                goal += days.count
                for date in days { plannedDates.insert(calendar.startOfDay(for: date)) }

            case .everyNDays:
                let interval = max(1, schedule.intervalDays)
                let completedThisWeek = completedSessions.reduce(into: 0) { count, session in
                    guard session.routine?.id == routine.id, session.endTime != nil else { return }
                    if week.contains(session.startTime) { count += 1 }
                }
                let liveLast = mostRecentCompletion(routineId: routine.id, sessions: completedSessions)
                let upcoming = upcomingCadenceDates(
                    startDate: schedule.startDate,
                    lastCompleted: liveLast,
                    intervalDays: interval,
                    count: 8,
                    referenceDate: referenceDate
                ).filter { $0 >= today && $0 < week.end }

                goal += completedThisWeek + upcoming.count
                for date in upcoming { plannedDates.insert(calendar.startOfDay(for: date)) }
            }
        }

        return PlannedWeek(goal: goal, plannedDates: plannedDates, week: week)
    }

    /// Most recent completed session date for a routine (any date), used as the
    /// live cadence anchor.
    private static func mostRecentCompletion(routineId: UUID, sessions: [WorkoutSession]) -> Date? {
        var latest: Date?
        for session in sessions {
            guard session.routine?.id == routineId, session.endTime != nil else { continue }
            if let current = latest {
                if session.startTime > current { latest = session.startTime }
            } else {
                latest = session.startTime
            }
        }
        return latest
    }

    // MARK: - Next due

    /// The next date this routine is due, or nil when it isn't planned.
    /// `.everyNDays` rolls off the *live* last completion (including this week),
    /// so the value updates the moment a workout is finished. A due date in the
    /// past means the routine is overdue.
    static func nextDue(
        for schedule: RoutineSchedule,
        lastCompleted: Date?,
        referenceDate: Date = Date()
    ) -> Date? {
        guard schedule.isActive else { return nil }
        let calendar = HistoryStatsService.isoGermanCalendar()
        let today = calendar.startOfDay(for: referenceDate)

        switch schedule.type {
        case .everyNDays:
            let interval = max(1, schedule.intervalDays)
            let (anchor, countsAsSession) = cadenceAnchor(
                startDate: schedule.startDate,
                lastCompleted: lastCompleted,
                calendar: calendar
            )
            if countsAsSession {
                // The reference date is the first planned session.
                if anchor >= today { return anchor }
                // Reference is in the past with no training since — the current
                // due day is the latest grid point up to today (overdue/today).
                let gapDays = calendar.dateComponents([.day], from: anchor, to: today).day ?? 0
                let steps = gapDays / interval
                return calendar.date(byAdding: .day, value: steps * interval, to: anchor)
            }
            // Rolling off the last completion (may be overdue → a past date).
            return calendar.date(byAdding: .day, value: interval, to: anchor)

        case .weekdays:
            let weekdays = schedule.weekdays
            guard !weekdays.isEmpty else { return nil }
            for offset in 0...13 {
                guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
                if weekdays.contains(isoWeekday(from: date, calendar: calendar)) {
                    return date
                }
            }
            return nil
        }
    }

    // MARK: - Cadence anchor

    /// The effective anchor of an `everyNDays` cadence.
    /// - Rolls off the last completion *on or after* the plan's reference date
    ///   (`startDate`) — the user's manually chosen "start fresh" point.
    /// - Otherwise falls back to the reference date itself, which counts as the
    ///   first planned session.
    /// Completions *before* the reference date are ignored, so picking a fresh
    /// reference date supersedes stale history until the routine is trained again.
    /// Returns `countsAsSession == true` only for the reference-date fallback
    /// (a real past completion is not a session still to be done).
    static func cadenceAnchor(
        startDate: Date,
        lastCompleted: Date?,
        calendar: Calendar
    ) -> (anchor: Date, countsAsSession: Bool) {
        let reference = calendar.startOfDay(for: startDate)
        if let lastCompleted {
            let lastDay = calendar.startOfDay(for: lastCompleted)
            if lastDay >= reference { return (lastDay, false) }
        }
        return (reference, true)
    }

    /// The next `count` upcoming cadence dates (>= today), anchored per
    /// `cadenceAnchor`. Forward-looking — an overdue plan previews from today
    /// rather than from missed past dates. Shared by the planning-sheet preview.
    static func upcomingCadenceDates(
        startDate: Date,
        lastCompleted: Date?,
        intervalDays: Int,
        count: Int,
        referenceDate: Date = Date()
    ) -> [Date] {
        let calendar = HistoryStatsService.isoGermanCalendar()
        let today = calendar.startOfDay(for: referenceDate)
        let interval = max(1, intervalDays)
        let (anchor, countsAsSession) = cadenceAnchor(
            startDate: startDate,
            lastCompleted: lastCompleted,
            calendar: calendar
        )

        // First candidate: the reference date itself when it counts as a
        // session, otherwise the day after the last completion.
        var date = countsAsSession
            ? anchor
            : (calendar.date(byAdding: .day, value: interval, to: anchor) ?? anchor)

        // Fast-forward onto the first grid point that is today or later.
        if date < today {
            let gapDays = calendar.dateComponents([.day], from: date, to: today).day ?? 0
            let steps = gapDays / interval
            date = calendar.date(byAdding: .day, value: steps * interval, to: date) ?? date
            while date < today {
                date = calendar.date(byAdding: .day, value: interval, to: date) ?? today
            }
        }

        var result: [Date] = []
        while result.count < count {
            result.append(date)
            guard let next = calendar.date(byAdding: .day, value: interval, to: date) else { break }
            date = next
        }
        return result
    }

    // MARK: - Helpers

    /// ISO weekday (1 = Monday … 7 = Sunday) from a date, independent of the
    /// calendar's Gregorian `.weekday` numbering (which is 1 = Sunday).
    static func isoWeekday(from date: Date, calendar: Calendar) -> Int {
        let gregorian = calendar.component(.weekday, from: date) // 1 = Sun … 7 = Sat
        return ((gregorian + 5) % 7) + 1
    }
}
