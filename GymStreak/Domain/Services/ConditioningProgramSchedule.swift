//
//  ConditioningProgramSchedule.swift
//  GymStreak
//
//  Where in the 12 weeks the user is today. Pure; everything is counted in
//  calendar days (`ConditioningProgramDay`) so pauses, time-zone changes and
//  DST boundaries never shift a week. See docs/fight-conditioning.md.
//

import Foundation

enum ConditioningProgramStatus: Equatable, Sendable {
    /// The chosen start day is still ahead.
    case notStarted(startsOn: ConditioningProgramDay)
    /// `week` is 1…12, `dayInWeek` 1…7. `isPaused` freezes both.
    case active(week: Int, dayInWeek: Int, isPaused: Bool)
    /// All 84 program days are behind the user.
    case completed
}

enum ConditioningProgramSchedule {

    static var totalDays: Int { ConditioningProgramContent.weekCount * ConditioningProgramContent.daysPerWeek }

    /// Program days that have passed before `day`: calendar days from the start day
    /// up to (not including) `day`, minus those inside a pause.
    ///
    /// On the day a pause begins the program day is unchanged, and it stays frozen
    /// until the pause ends — the user resumes on the day they paused.
    static func programDay(on day: ConditioningProgramDay, enrollment: ConditioningProgramEnrollment, calendar: Calendar) -> Int {
        let elapsed = enrollment.startDay.days(to: day, calendar: calendar)
        guard elapsed > 0 else { return elapsed }
        var paused = 0
        for pause in enrollment.pauses {
            paused += overlap(from: pause.from, until: pause.until, start: enrollment.startDay, end: day, calendar: calendar)
        }
        if let pausedSince = enrollment.pausedSince {
            paused += overlap(from: pausedSince, until: day, start: enrollment.startDay, end: day, calendar: calendar)
        }
        return elapsed - paused
    }

    static func status(on day: ConditioningProgramDay, enrollment: ConditioningProgramEnrollment, calendar: Calendar) -> ConditioningProgramStatus {
        let programDay = programDay(on: day, enrollment: enrollment, calendar: calendar)
        if programDay < 0 { return .notStarted(startsOn: enrollment.startDay) }
        if programDay >= totalDays { return .completed }
        return .active(
            week: programDay / ConditioningProgramContent.daysPerWeek + 1,
            dayInWeek: programDay % ConditioningProgramContent.daysPerWeek + 1,
            isPaused: enrollment.isPaused
        )
    }

    /// The calendar day the current program week began on, for counting the
    /// sessions logged "this week". A pause inside the week stays inside the range.
    static func currentWeekStart(on day: ConditioningProgramDay, enrollment: ConditioningProgramEnrollment, calendar: Calendar) -> ConditioningProgramDay {
        let programDay = programDay(on: day, enrollment: enrollment, calendar: calendar)
        guard programDay > 0 else { return enrollment.startDay }
        let weekStartProgramDay = programDay - programDay % ConditioningProgramContent.daysPerWeek
        // Walk back from today until the program day drops below the week start; the
        // day after that is the week's first day. Bounded by the week plus any pause in it.
        var candidate = day
        while true {
            let previous = candidate.adding(days: -1, calendar: calendar)
            if previous < enrollment.startDay
                || Self.programDay(on: previous, enrollment: enrollment, calendar: calendar) < weekStartProgramDay {
                return candidate
            }
            candidate = previous
        }
    }

    /// Calendar days in `from ..< until` that also lie in `start ..< end`.
    private static func overlap(
        from: ConditioningProgramDay,
        until: ConditioningProgramDay,
        start: ConditioningProgramDay,
        end: ConditioningProgramDay,
        calendar: Calendar
    ) -> Int {
        let lower = max(from, start)
        let upper = min(until, end)
        return max(0, lower.days(to: upper, calendar: calendar))
    }
}
