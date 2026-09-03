//
//  WeekdayScheduleHintPolicy.swift
//  GymStreak
//
//  P9's discovery surface, as pure logic over a schedule and a date: does this
//  cadence plan look like a weekly schedule that has slipped off its day?
//  See docs/monetization-strategy.md §2 and docs/calendar-sync.md §14e.
//

import Foundation

/// Decides whether a routine's plan is a **weekly rhythm expressed with the
/// wrong tool** — the one situation where fixed weekdays (P9) are the exact fix.
///
/// Pure and isolation-agnostic like `ScheduleGatingPolicy`, and for the same
/// reason: no SwiftUI, no entitlement, no persistence. **It does not decide
/// whether to show anything** — that needs the entitlement and belongs to
/// `RoutinesViewModel`, which asks `ScheduleGatingPolicy.isSubjectToGate(...)`
/// rather than re-deriving the rule here.
///
/// ## Why the two obvious signals are wrong
///
/// **"The plan moved" fires for everyone, forever.** `.everyNDays` re-anchors on
/// the live last completion (`WorkoutPlanningService.cadenceAnchor`), so it moves
/// after nearly every session. That is the feature working, not drift.
///
/// **"The weekday changed" fires for everyone on a non-weekly interval.** For any
/// interval not divisible by 7 the weekday rotates *by construction* —
/// every-3-days is *supposed* to walk around the week, and nudging that user
/// toward fixed weekdays pushes them off the tool they deliberately chose.
///
/// What is left is narrow and honest: an interval that is a **multiple of 7** is
/// only ever chosen to express a weekly rhythm, and a plan that has since landed
/// on a different weekday than the one it started on has lost the thing the user
/// picked it for. They asked for "every Wednesday", the cadence gave them "every
/// 7 days", and training late once moved it to Thursday permanently.
///
/// Stateless on purpose: computed from `type`, `intervalDays`, `startDate` and
/// `isActive`, all of which `RoutineSchedule` already stores. No counter, no
/// `UserDefaults`, and above all no new `@Model` property — that would be
/// CloudKit schema surface and a production schema deploy for a nudge.
enum WeekdayScheduleHintPolicy {

    /// The ISO weekday (1 = Monday … 7 = Sunday) the plan **started** on when it
    /// has since drifted off it, or `nil` when there is nothing to say.
    ///
    /// The start weekday, not the current one, because that is the day the user
    /// meant — it is what the hint offers to restore.
    ///
    /// Returns `nil` for a paused plan, a weekday plan, a non-weekly interval,
    /// and a plan still on its original day. The last of those is what makes the
    /// hint disappear by itself once the user re-anchors, with nothing to reset.
    static func driftedStartWeekday(
        for schedule: RoutineSchedule,
        lastCompleted: Date?,
        referenceDate: Date = Date()
    ) -> Int? {
        guard schedule.isActive, schedule.type == .everyNDays else { return nil }
        // `>= 7` as well as the modulo: `intervalDays` is defaulted and could be
        // 0, which passes `% 7 == 0` and means nothing. `WorkoutPlanningService`
        // clamps it to `max(1, …)`, so a 0 here is a weekly rhythm to nobody.
        guard schedule.intervalDays >= 7, schedule.intervalDays % 7 == 0 else { return nil }

        let calendar = HistoryStatsService.isoGermanCalendar()
        guard let nextDue = WorkoutPlanningService.nextDue(
            for: schedule,
            lastCompleted: lastCompleted,
            referenceDate: referenceDate
        ) else { return nil }

        let startWeekday = WorkoutPlanningService.isoWeekday(from: schedule.startDate, calendar: calendar)
        let dueWeekday = WorkoutPlanningService.isoWeekday(from: nextDue, calendar: calendar)
        return startWeekday == dueWeekday ? nil : startWeekday
    }
}
