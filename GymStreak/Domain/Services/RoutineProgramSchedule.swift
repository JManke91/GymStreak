//
//  RoutineProgramSchedule.swift
//  GymStreak
//
//  When each routine of a program is first due, from the user's "first
//  workout" choice. One function feeds both the install sheet's preview and
//  the plan the installer writes, so the two cannot disagree.
//  See docs/routine-programs.md.
//

import Foundation

/// The install sheet's "First workout" picker.
enum ProgramStartChoice: Hashable, Sendable {
    case today
    case tomorrow
    case day(Date)
}

struct ProgramRoutineStart: Equatable, Sendable {
    let seedKey: String
    /// Start of the day the routine is first due — the cadence's `startDate`.
    let firstDate: Date
}

enum RoutineProgramSchedule {

    /// Start of the day the program's first workout falls on.
    static func firstWorkoutDay(for choice: ProgramStartChoice, now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        switch choice {
        case .today:
            return today
        case .tomorrow:
            return calendar.date(byAdding: .day, value: 1, to: today) ?? today
        case .day(let date):
            return max(today, calendar.startOfDay(for: date))
        }
    }

    /// The first due day of each routine being added, in program order.
    ///
    /// Offsets are taken relative to the **earliest routine being added**, not to
    /// the program's first routine: restoring only a deleted Full Body B puts it
    /// on the chosen day rather than two days after it.
    static func firstDueDates(
        for routines: [RoutineProgramRoutine],
        firstWorkoutDay: Date,
        calendar: Calendar
    ) -> [ProgramRoutineStart] {
        guard let base = routines.map(\.startOffsetDays).min() else { return [] }
        let day = calendar.startOfDay(for: firstWorkoutDay)
        return routines.map { routine in
            let date = calendar.date(byAdding: .day, value: routine.startOffsetDays - base, to: day) ?? day
            return ProgramRoutineStart(seedKey: routine.seedKey, firstDate: date)
        }
    }
}
