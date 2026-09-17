//
//  ReEngagementNudgePlanner.swift
//  GymStreak
//
//  The two "come back" triggers: a planned session that passed with nothing
//  logged, and — for users with no plan to miss — a stretch of days without a
//  workout. Pure logic; the cap and the merge with planned-session reminders
//  live in `WorkoutReminderPlanner`. See docs/workout-reminders.md.
//

import Foundation

/// Which days deserve a nudge asking a user who has drifted to train again.
///
/// **Neither trigger reads a streak.** The only streak in the app is
/// `HistoryStatsService.streakWeeks` — consecutive *weeks* with a finished
/// workout — which has no crisp "about to lapse" moment, and inventing a daily
/// streak would put a different number in the notification than the Verlauf
/// tab shows. The schedule drives the nudge when there is one; dormancy covers
/// everyone else, which is most of the users who launch once and never return.
///
/// Both are computed **ahead of time**. A user who has stopped opening the app
/// never runs a refresh, so a nudge that is only scheduled once the lapse is
/// observed would never reach the population it exists for. Each pass therefore
/// schedules the nudges that *would* be due if nothing is logged in between, and
/// the refresh that follows every completed workout withdraws them.
enum ReEngagementNudgePlanner {

    /// Days without a completed workout before the dormancy nudge fires. A single
    /// missed day is not a lapse; four is past a normal rest-day rhythm and still
    /// inside the first week, where a return is most likely.
    static let dormancyThresholdDays = 4

    /// Days between dormancy nudges within one lapse — at most one per rolling
    /// seven days.
    static let dormancySpacingDays = 7

    /// How many dormancy nudges one lapse can produce before the app goes quiet
    /// until the user trains again. Two unanswered nudges are an answer, and a
    /// third is where a nudge starts earning a notification revocation.
    static let maxDormancyNudgesPerLapse = 2

    /// The missed-session nudges implied by `plannedDays`, keyed by the day each
    /// nudge lands on — the day after the planned session — with the routine to
    /// name, or `nil` when that planned day carried more than one routine.
    ///
    /// A planned day is not missed when **any** workout was completed on or after
    /// it: a user who trained a different routine that day, or who catches up the
    /// next morning, has not drifted, and a "still waiting" message right after a
    /// workout is exactly the notification this feature must never send.
    ///
    /// - Parameter plannedDays: start-of-day → names of the routines planned that
    ///   day, including days already past.
    /// - Parameter lastWorkoutDate: start date of the most recent completed
    ///   workout of any routine.
    static func missedSessionNudges(
        plannedDays: [Date: [String]],
        lastWorkoutDate: Date?,
        calendar: Calendar
    ) -> [Date: String?] {
        let lastWorkoutDay = lastWorkoutDate.map { calendar.startOfDay(for: $0) }
        var nudges: [Date: String?] = [:]
        for (plannedDay, names) in plannedDays {
            if let lastWorkoutDay, lastWorkoutDay >= plannedDay { continue }
            guard let nudgeDay = calendar.date(byAdding: .day, value: 1, to: plannedDay) else {
                continue
            }
            nudges[nudgeDay] = names.count == 1 ? names[0] : nil
        }
        return nudges
    }

    /// The days the dormancy nudge lands on for the current lapse.
    ///
    /// The lapse is measured from the most recent completed workout, or — for a
    /// user who has never completed one — from `firstSeenAt`, the install-date
    /// stand-in. Without either there is nothing to measure from, and nothing is
    /// nudged.
    ///
    /// Callers apply this only to users with **no active plan**: a user on a
    /// once-a-week plan is not dormant four days after training, and the planned
    /// reminder and missed-session nudge already speak for scheduled users.
    static func dormancyNudgeDays(
        lastWorkoutDate: Date?,
        firstSeenAt: Date?,
        calendar: Calendar
    ) -> [Date] {
        guard let anchor = lastWorkoutDate ?? firstSeenAt else { return [] }
        let anchorDay = calendar.startOfDay(for: anchor)
        return (0..<maxDormancyNudgesPerLapse).compactMap { index in
            calendar.date(
                byAdding: .day,
                value: dormancyThresholdDays + index * dormancySpacingDays,
                to: anchorDay
            )
        }
    }
}
