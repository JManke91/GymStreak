//
//  ReminderFrequencyPolicy.swift
//  GymStreak
//
//  The hard cap on how often the app may notify a user about training, in one
//  file so a reviewer can read the whole rule without tracing the scheduler.
//  See docs/workout-reminders.md.
//

import Foundation

/// How many reminders the app is allowed to send, and how close together.
///
/// **This is the whole cap.** It is a policy type rather than an emergent
/// property of the scheduling logic because it is the mechanism in this app most
/// able to damage `docs/monetization-strategy.md` §10's App Store-rating
/// guardrail, and a guardrail nobody can find in one place is not a guardrail.
/// Every reminder the app can send — the planned-session reminder, the
/// missed-session nudge and the dormancy nudge — passes through
/// `admissibleDays(from:alreadyReminded:calendar:)`. **A new reminder kind adds
/// a candidate, never a second cap.**
///
/// The numbers are a starting point and are meant to be retuned downwards on
/// evidence, never upwards without it: a user who trains five days a week gets
/// three reminders, not five, and the two they do not get cost them nothing —
/// they were already training.
enum ReminderFrequencyPolicy {

    /// At most one notification on any single calendar day, across every
    /// reminder kind. Two reminders in one day is the shape that reads as an app
    /// nagging rather than helping.
    static let maxRemindersPerDay = 1

    /// At most this many notifications in any `rollingWindowDays`-long window.
    /// Three is below the point where a weekly rhythm starts to feel like a
    /// daily one, and it still covers the common three-day training splits.
    static let maxRemindersPerRollingWindow = 3

    /// The length of the rolling window, in days. Seven, so the cap is read
    /// against the week the user actually plans in.
    static let rollingWindowDays = 7

    /// Whether `day` may carry a reminder, given the days that already do.
    ///
    /// **Every** `rollingWindowDays`-long window that contains `day` is checked,
    /// not only the one ending at it. A backward-only check is enough while
    /// candidates arrive strictly earliest-first, but the planner admits in two
    /// tiers — planned sessions first, nudges into what is left — so a nudge can
    /// be offered a day *earlier* than reminders already accepted, and only the
    /// forward windows would see it push one of those past the limit.
    static func allowsReminder(
        on day: Date,
        given remindedDays: [Date],
        calendar: Calendar
    ) -> Bool {
        let target = calendar.startOfDay(for: day)
        let taken = remindedDays.map { calendar.startOfDay(for: $0) }
        guard taken.filter({ $0 == target }).count < maxRemindersPerDay else { return false }

        for offset in 0..<rollingWindowDays {
            guard let windowStart = calendar.date(byAdding: .day, value: -offset, to: target),
                  let windowEnd = calendar.date(
                      byAdding: .day,
                      value: rollingWindowDays - 1,
                      to: windowStart
                  ) else { return false }
            let inWindow = taken.filter { $0 >= windowStart && $0 <= windowEnd }.count
            guard inWindow < maxRemindersPerRollingWindow else { return false }
        }
        return true
    }

    /// The subset of `candidates` the cap allows, taken **earliest first**.
    ///
    /// Earliest-first *within one tier*: the soonest planned session is the one
    /// the reminder can still change the outcome of, and a later day the cap
    /// refuses today may well be admitted on a later pass, once the days now in
    /// the window have fallen out of it. Priority *between* kinds is the
    /// planner's call, made by passing a higher tier's admitted days in as
    /// `alreadyReminded` (`WorkoutReminderPlanner`).
    ///
    /// - Parameter alreadyReminded: days that already carry a reminder and are
    ///   not being re-planned — in practice the past days of the ledger.
    static func admissibleDays(
        from candidates: [Date],
        alreadyReminded: [Date],
        calendar: Calendar
    ) -> [Date] {
        var taken = alreadyReminded.map { calendar.startOfDay(for: $0) }
        var accepted: [Date] = []
        for candidate in candidates.map({ calendar.startOfDay(for: $0) }).sorted() {
            guard allowsReminder(on: candidate, given: taken, calendar: calendar) else { continue }
            taken.append(candidate)
            accepted.append(candidate)
        }
        return accepted
    }

    /// The days of a ledger that can still constrain a future reminder —
    /// everything older than one window back is dead weight.
    static func prune(
        _ days: [Date],
        referenceDate: Date,
        calendar: Calendar
    ) -> [Date] {
        let today = calendar.startOfDay(for: referenceDate)
        guard let oldest = calendar.date(
            byAdding: .day,
            value: -(rollingWindowDays - 1),
            to: today
        ) else { return days }
        return days
            .map { calendar.startOfDay(for: $0) }
            .filter { $0 >= oldest }
            .sorted()
    }
}
