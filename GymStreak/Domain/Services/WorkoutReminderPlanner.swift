//
//  WorkoutReminderPlanner.swift
//  GymStreak
//
//  Turns the user's plans and training history into the days a training
//  reminder or re-engagement nudge should land on. Pure logic over model
//  arrays; nothing here knows what a notification is.
//  See docs/workout-reminders.md.
//

import Foundation

/// Which mornings the app should speak to the user about training, and why.
///
/// **It reads the plan through `WorkoutPlanningService`, never around it.** The
/// cadence anchor in particular is `WorkoutPlanningService.cadenceAnchor` via
/// `upcomingCadenceDates` — the same helper the Verlauf tab's weekly goal, the
/// routine cards' next-due pill and the Apple Calendar mirror all go through. A
/// second forward walk here is exactly how the reminder and the day-strip would
/// come to disagree about which day is planned.
///
/// Entitlement-unaware, like `WorkoutPlanningService` and
/// `PlannedWorkoutCalendarStateBuilder`: a weekday plan built while subscribed
/// keeps being reminded after a lapse, because a notification about the user's
/// own plan is not a Pro capability (docs/workout-planning.md, "Pro gating").
enum WorkoutReminderPlanner {

    /// The hour every reminder kind fires, in the user's local time.
    ///
    /// Morning, and early enough to still be a decision rather than a report:
    /// 08:00 leaves the whole day to act on. Not configurable — a preference
    /// nobody finds is not worth the surface, and the cap matters far more than
    /// the hour. Shared by all kinds, because the scheduler's ledger decides
    /// "already spoken" from this one fire time.
    static let reminderHour = 8

    /// The minute within `reminderHour`. On the hour, deliberately: a reminder
    /// at 08:07 reads as a bug, not as a considered time.
    static let reminderMinute = 0

    /// How far ahead reminders are scheduled.
    ///
    /// Two weeks: long enough that a user who does not open the app for a
    /// fortnight still gets reminded, short enough that a stale window cannot
    /// outlive the plan by much. It is also comfortably inside the 64 pending
    /// requests iOS keeps per app — the cap allows at most six in this window.
    static let horizonDays = 14

    /// Why a reminder is sent. Declared in priority order: when two kinds want
    /// the same day, or the cap has room for only some, the earlier case wins.
    enum Kind: CaseIterable {
        /// The morning of a planned training day.
        case plannedSession
        /// The morning after a planned day that passed with nothing logged.
        case missedSession
        /// A stretch without any workout, for users with no plan to miss.
        case dormancy
    }

    /// One reminder, on one day.
    struct Reminder: Equatable {
        /// Start of the day the reminder belongs to. The day, not the fire
        /// date, is what the frequency cap and the ledger are keyed on.
        let day: Date
        /// The exact moment the notification fires.
        let fireDate: Date
        let kind: Kind
        /// The routine to name in the body, or `nil` when there is none or
        /// more than one — in which case the copy stays general rather than
        /// picking a winner.
        let routineName: String?
    }

    /// The reminders to schedule, earliest first and already capped.
    ///
    /// **One cap, admitted in tiers.** Planned-session reminders are admitted
    /// first; missed-session nudges take what room is left, then dormancy
    /// nudges. A nudge is speculative — it is withdrawn the moment the user
    /// trains — so it must never displace a reminder about a session the user
    /// actually planned. A user already reminded three times a week is being
    /// spoken to at the limit, and gets no nudge on top.
    ///
    /// - Parameter lastCompleted: most recent completed-session start date per
    ///   routine id, as `WorkoutSessionRepository.lastCompletedStartDates`
    ///   returns it. This is what rolls an `.everyNDays` cadence forward.
    /// - Parameter lastWorkoutDate: start date of the most recent completed
    ///   workout of any routine — what clears a missed session and ends a lapse.
    /// - Parameter firstSeenAt: install-date stand-in, the dormancy anchor for a
    ///   user who has never completed a workout.
    /// - Parameter alreadyReminded: days that already carry a reminder and are
    ///   not being re-planned — the past days of the scheduler's ledger.
    static func reminders(
        routines: [Routine],
        lastCompleted: [UUID: Date],
        lastWorkoutDate: Date? = nil,
        firstSeenAt: Date? = nil,
        alreadyReminded: [Date],
        referenceDate: Date = Date()
    ) -> [Reminder] {
        let calendar = HistoryStatsService.isoGermanCalendar()
        let today = calendar.startOfDay(for: referenceDate)
        guard let horizonEnd = calendar.date(byAdding: .day, value: horizonDays, to: today) else {
            return []
        }

        let plannedDays = plannedDays(
            routines: routines,
            lastCompleted: lastCompleted,
            referenceDate: referenceDate,
            horizonEnd: horizonEnd,
            calendar: calendar
        )

        // Day → the winning kind and the routine it names. Filled in priority
        // order, so a day wanted by two kinds keeps the more important one.
        var wanted: [Date: (kind: Kind, routineName: String?)] = [:]
        for (day, names) in plannedDays where day >= today {
            wanted[day] = (.plannedSession, names.count == 1 ? names[0] : nil)
        }
        let missed = ReEngagementNudgePlanner.missedSessionNudges(
            plannedDays: plannedDays,
            lastWorkoutDate: lastWorkoutDate,
            calendar: calendar
        )
        for (day, name) in missed where wanted[day] == nil {
            wanted[day] = (.missedSession, name)
        }
        if !hasActivePlan(routines) {
            let dormant = ReEngagementNudgePlanner.dormancyNudgeDays(
                lastWorkoutDate: lastWorkoutDate,
                firstSeenAt: firstSeenAt,
                calendar: calendar
            )
            for day in dormant where wanted[day] == nil {
                wanted[day] = (.dormancy, nil)
            }
        }

        // A day whose fire time has already passed cannot be reminded about —
        // and must not be counted against the cap, or a user opening the app in
        // the afternoon would spend the day's allowance on a notification that
        // never existed.
        let candidates = wanted.compactMap { entry -> Reminder? in
            guard entry.key < horizonEnd,
                  let fireDate = fireDate(for: entry.key, calendar: calendar),
                  fireDate > referenceDate else { return nil }
            return Reminder(
                day: entry.key,
                fireDate: fireDate,
                kind: entry.value.kind,
                routineName: entry.value.routineName
            )
        }

        var taken = alreadyReminded
        var admitted: [Reminder] = []
        for kind in Kind.allCases {
            let tier = candidates.filter { $0.kind == kind }
            let days = Set(ReminderFrequencyPolicy.admissibleDays(
                from: tier.map(\.day),
                alreadyReminded: taken,
                calendar: calendar
            ))
            taken += days
            admitted += tier.filter { days.contains($0.day) }
        }
        return admitted.sorted { $0.day < $1.day }
    }

    /// The moment a reminder for `day` fires.
    ///
    /// Built from calendar components rather than by adding seconds to the start
    /// of the day, so it lands at 08:00 wall-clock on the days a DST transition
    /// makes 23 or 25 hours long.
    static func fireDate(for day: Date, calendar: Calendar) -> Date? {
        calendar.date(
            bySettingHour: reminderHour,
            minute: reminderMinute,
            second: 0,
            of: calendar.startOfDay(for: day)
        )
    }

    // MARK: - Plans

    /// Whether any routine carries a plan that can put a session on a day — the
    /// line between "a scheduled user" and "a user with nothing to miss".
    static func hasActivePlan(_ routines: [Routine]) -> Bool {
        routines.contains { routine in
            guard let schedule = routine.schedule, schedule.isActive else { return false }
            return schedule.type == .everyNDays || !schedule.weekdays.isEmpty
        }
    }

    /// Start-of-day → names of the routines planned on it, from **yesterday**
    /// up to `horizonEnd`. Yesterday is included so a session missed yesterday
    /// can still earn this morning's nudge.
    private static func plannedDays(
        routines: [Routine],
        lastCompleted: [UUID: Date],
        referenceDate: Date,
        horizonEnd: Date,
        calendar: Calendar
    ) -> [Date: [String]] {
        let today = calendar.startOfDay(for: referenceDate)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return [:] }

        var routinesByDay: [Date: [String]] = [:]
        for routine in routines {
            guard let schedule = routine.schedule, schedule.isActive else { continue }

            let days: [Date]
            switch schedule.type {
            case .everyNDays:
                let interval = max(1, schedule.intervalDays)
                // Walked from yesterday, which stays on the same grid as a walk
                // from today — the fast-forward steps in whole intervals.
                days = WorkoutPlanningService.upcomingCadenceDates(
                    startDate: schedule.startDate,
                    lastCompleted: lastCompleted[routine.id],
                    intervalDays: interval,
                    // Enough occurrences to fill the horizon whatever the
                    // cadence, plus slack so the walk is never what truncates it.
                    count: (horizonDays + 1) / interval + 2,
                    referenceDate: yesterday
                )

            case .weekdays:
                let weekdays = schedule.weekdays
                // No day selected is not a plan — `nextDue` answers nil for it
                // too (docs/workout-planning.md).
                guard !weekdays.isEmpty else { continue }
                days = (-1..<horizonDays).compactMap { offset in
                    guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                          weekdays.contains(
                              WorkoutPlanningService.isoWeekday(from: day, calendar: calendar)
                          ) else { return nil }
                    return day
                }
            }

            // A past day predating the plan itself was never planned: a user who
            // sets up a Monday plan on Tuesday has not missed Monday.
            let planCreated = calendar.startOfDay(for: schedule.createdAt)
            for day in days {
                let start = calendar.startOfDay(for: day)
                guard start < horizonEnd, start >= today || start >= planCreated else { continue }
                routinesByDay[start, default: []].append(routine.name)
            }
        }
        return routinesByDay
    }
}
