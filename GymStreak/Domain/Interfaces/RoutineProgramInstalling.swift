//
//  RoutineProgramInstalling.swift
//  GymStreak
//
//  Installs a ready-made program as ordinary routines. See
//  docs/routine-programs.md → "Install contract".
//

import Foundation

@MainActor
protocol RoutineProgramInstalling: AnyObject {
    /// The `seedKey`s of every seeded routine currently in the store. Program
    /// membership and "installed" are derived from these.
    func installedRoutineKeys() -> Set<String>

    /// Inserts the program's routines whose `seedKey` is not already present
    /// (gap-filling — never a second copy). With `firstWorkoutDay`, each
    /// inserted routine gets an every-`cadenceDays` plan starting per
    /// `RoutineProgramSchedule.firstDueDates`; without it, no plan is written.
    ///
    /// - Returns: how many routines were inserted.
    @discardableResult
    func install(_ program: RoutineProgram, firstWorkoutDay: Date?) throws -> Int
}
