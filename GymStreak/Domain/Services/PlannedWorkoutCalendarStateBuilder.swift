//
//  PlannedWorkoutCalendarStateBuilder.swift
//  GymStreak
//
//  Turns the user's routines and their training history into the state the
//  calendar should be in. Reads the plan through the very same
//  `WorkoutPlanningService` helpers every other surface uses, so the calendar
//  tells the user exactly what the app tells itself — no more, no further.
//  See docs/calendar-sync.md.
//

import Foundation

enum PlannedWorkoutCalendarStateBuilder {

    /// How many occurrences of each planned **cadence** routine the calendar
    /// carries.
    ///
    /// Far enough ahead that the calendar looks planned rather than sparse,
    /// short enough that a window left stale by an app nobody has opened in
    /// weeks is not embarrassing — and for the common 3-to-5-day cadences it is
    /// roughly a month of lookahead. Weekday plans need no equivalent: they are
    /// one open-ended recurrence and never run dry.
    static let horizonPerRoutine = 8

    /// The state to mirror, in routine order.
    ///
    /// **The plan shape picks the calendar shape**, and the split falls exactly
    /// on `RoutineScheduleType`:
    ///
    /// - `.everyNDays` → a bounded rolling window of one-shot events. A cadence
    ///   is not a fixed grid: `WorkoutPlanningService.cadenceAnchor` re-derives
    ///   it from the last completed session, so the whole series moves forward
    ///   every time the user trains. An `EKRecurrenceRule` would have to be
    ///   destroyed and recreated after almost every workout, and would promise an
    ///   infinite tail of occurrences that depend on completions which have not
    ///   happened yet.
    /// - `.weekdays` → one open-ended repeating event. Mon/Wed/Fri does not move
    ///   when the user trains late, so it genuinely *is* a recurrence — and being
    ///   one is what keeps the calendar populated months out for a user who has
    ///   not opened the app (docs/calendar-sync.md §13a).
    ///
    /// **Entitlement-unaware, like `WorkoutPlanningService` itself.** No `isPro`
    /// reaches this type: a plan built while subscribed keeps mirroring after a
    /// lapse, exactly as its weekly goal and day-strip markers do. Fixed-weekday
    /// plans are Pro to *create* (P9) and that gate lives in `RoutinesViewModel`
    /// alone.
    ///
    /// - Parameter lastCompleted: most recent completed-session start date per
    ///   routine id, as `WorkoutSessionRepository.lastCompletedStartDates` returns.
    static func state(
        routines: [Routine],
        lastCompleted: [UUID: Date],
        referenceDate: Date = Date()
    ) -> PlannedWorkoutCalendarState {
        let titleFormat = "calendar_sync.event.title_format".localized
        var state = PlannedWorkoutCalendarState()

        for routine in routines {
            guard let schedule = routine.schedule, schedule.isActive else { continue }
            let title = String(format: titleFormat, routine.name)

            switch schedule.type {
            case .everyNDays:
                let days = WorkoutPlanningService.upcomingCadenceDates(
                    startDate: schedule.startDate,
                    lastCompleted: lastCompleted[routine.id],
                    intervalDays: schedule.intervalDays,
                    count: horizonPerRoutine,
                    referenceDate: referenceDate
                )
                for day in days {
                    state.occurrences.append(
                        PlannedWorkoutOccurrence(routineId: routine.id, day: day, title: title)
                    )
                }

            case .weekdays:
                let weekdays = schedule.weekdays
                // No day selected is not a plan; `nextDue` answers `nil` for it
                // too, and the guard below would drop it anyway.
                guard !weekdays.isEmpty else { continue }
                // The series starts on the first upcoming occurrence, taken from
                // the very helper that labels the routine card — deliberately not
                // a second forward scan of its own, which is how the calendar and
                // the card would come to disagree.
                guard let firstDay = WorkoutPlanningService.nextDue(
                    for: schedule,
                    lastCompleted: lastCompleted[routine.id],
                    referenceDate: referenceDate
                ) else { continue }
                state.series.append(
                    PlannedWorkoutSeries(
                        routineId: routine.id,
                        weekdays: weekdays,
                        firstDay: firstDay,
                        title: title
                    )
                )
            }
        }
        return state
    }
}
