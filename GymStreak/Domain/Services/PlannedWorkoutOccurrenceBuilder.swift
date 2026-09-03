//
//  PlannedWorkoutOccurrenceBuilder.swift
//  GymStreak
//
//  Turns the user's routines and their training history into the list of
//  occurrences the calendar should show. Reads the plan through the very same
//  `WorkoutPlanningService` helper every other surface uses, so the calendar
//  tells the user exactly what the app tells itself — no more, no further.
//  See docs/calendar-sync.md.
//

import Foundation

enum PlannedWorkoutOccurrenceBuilder {

    /// How many occurrences of each planned routine the calendar carries.
    ///
    /// Far enough ahead that the calendar looks planned rather than sparse,
    /// short enough that a window left stale by an app nobody has opened in
    /// weeks is not embarrassing — and for the common 3-to-5-day cadences it is
    /// roughly a month of lookahead.
    static let horizonPerRoutine = 8

    /// The occurrences to mirror, in routine order.
    ///
    /// **Cadence plans only, deliberately.** A rolling `everyNDays` plan is not a
    /// fixed grid: `WorkoutPlanningService.cadenceAnchor` re-derives it from the
    /// last completed session, so the whole series moves forward every time the
    /// user trains. A bounded forward window of one-shot events is the only
    /// honest way to express that — an `EKRecurrenceRule` would have to be
    /// destroyed and recreated after almost every workout, and would promise an
    /// infinite tail of occurrences that depend on completions which have not
    /// happened yet. Fixed-weekday plans genuinely *are* a recurrence and are
    /// modelled as one separately (ticket 04); until then they contribute
    /// nothing here.
    ///
    /// **Entitlement-unaware, like `WorkoutPlanningService` itself.** No `isPro`
    /// reaches this type: a plan built while subscribed keeps mirroring after a
    /// lapse, exactly as its weekly goal and day-strip markers do.
    ///
    /// - Parameter lastCompleted: most recent completed-session start date per
    ///   routine id, as `WorkoutSessionRepository.lastCompletedStartDates` returns.
    static func occurrences(
        routines: [Routine],
        lastCompleted: [UUID: Date],
        referenceDate: Date = Date()
    ) -> [PlannedWorkoutOccurrence] {
        let titleFormat = "calendar_sync.event.title_format".localized
        var result: [PlannedWorkoutOccurrence] = []

        for routine in routines {
            guard let schedule = routine.schedule,
                  schedule.isActive,
                  schedule.type == .everyNDays else { continue }

            let title = String(format: titleFormat, routine.name)
            let days = WorkoutPlanningService.upcomingCadenceDates(
                startDate: schedule.startDate,
                lastCompleted: lastCompleted[routine.id],
                intervalDays: schedule.intervalDays,
                count: horizonPerRoutine,
                referenceDate: referenceDate
            )
            for day in days {
                result.append(
                    PlannedWorkoutOccurrence(routineId: routine.id, day: day, title: title)
                )
            }
        }
        return result
    }
}
