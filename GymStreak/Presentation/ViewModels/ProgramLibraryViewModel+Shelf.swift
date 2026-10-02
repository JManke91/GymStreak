//
//  ProgramLibraryViewModel+Shelf.swift
//  GymStreak
//
//  The Routines tab's Programs shelf and its "Start with a program" empty
//  state (design artboards 1, 5, 6). See docs/routine-programs.md.
//

import Foundation

extension ProgramLibraryViewModel {

    /// One cell of a shelf card's 7-day pattern.
    struct PatternDay: Identifiable, Equatable {
        let id: Int
        /// The routine's letter ("A"), nil on a rest day.
        let label: String?
    }

    /// Everything a shelf card and an empty-state row show. The content is built
    /// once from the static catalog; only `isAdded` moves, in `refresh()`.
    struct ShelfCard: Identifiable, Equatable {
        let id: String
        let level: String
        let name: String
        let pitch: String
        /// "2 routines".
        let routineCount: String
        let pattern: [PatternDay]
        /// "~3–4 sessions a week".
        let cadence: String
        /// "FB" — the empty state's monogram.
        let mark: String
        /// "Beginner · 2 routines · 3–4× a week" — the empty state's row.
        let meta: String
        /// At least one of the program's routines is in the user's list.
        var isAdded = false
    }

    static func shelfCard(for program: RoutineProgram) -> ShelfCard {
        let key = "routine_programs.\(program.id)"
        let level = "\(key).level".localized
        // The pattern does not depend on the date: any day works as the start.
        let pattern = RoutineProgramSchedule.timeline(
            for: program,
            from: Date(timeIntervalSinceReferenceDate: 0),
            dayCount: 7,
            calendar: Calendar(identifier: .gregorian)
        )
        return ShelfCard(
            id: program.id,
            level: level,
            name: "\(key).name".localized,
            pitch: "\(key).pitch_shelf".localized,
            routineCount: String(format: "routine_programs.shelf.routine_count".localized, program.routines.count),
            pattern: pattern.enumerated().map { index, day in
                PatternDay(id: index, label: day.routineSeedKey.map { "\($0).short".localized })
            },
            cadence: "\(key).cadence".localized,
            mark: "\(key).mark".localized,
            meta: String(
                format: "routine_programs.empty.meta".localized,
                level,
                program.routines.count,
                "\(key).stat.frequency".localized
            )
        )
    }
}
