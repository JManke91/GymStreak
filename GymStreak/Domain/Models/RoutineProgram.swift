//
//  RoutineProgram.swift
//  GymStreak
//
//  A ready-made training program (Beginner Full Body, …) as static content.
//  Installing one creates ordinary routines keyed by `RoutineProgramRoutine.seedKey`
//  — there is no program model in the store. See docs/routine-programs.md.
//

import Foundation

/// One exercise slot of a program routine.
struct RoutineProgramExercise: Sendable, Equatable {
    /// Full `SeedExerciseCatalog` key, e.g. "seed.exercise.barbell_back_squat".
    let exerciseSeedKey: String
    let setCount: Int
    /// Rep-range goal. Every set starts at `repMin`, the bottom of the range.
    let repMin: Int
    let repMax: Int
    let restTime: TimeInterval
    /// Slots sharing a non-nil group are performed as a superset, in order.
    let supersetGroup: String?
    /// Swap-in exercises, already set up with the primary's scheme.
    let alternativeSeedKeys: [String]

    init(
        _ exerciseSeedKey: String,
        sets setCount: Int,
        reps: ClosedRange<Int>,
        rest restTime: TimeInterval,
        superset supersetGroup: String? = nil,
        alternatives alternativeSeedKeys: [String] = []
    ) {
        self.exerciseSeedKey = exerciseSeedKey
        self.setCount = setCount
        self.repMin = reps.lowerBound
        self.repMax = reps.upperBound
        self.restTime = restTime
        self.supersetGroup = supersetGroup
        self.alternativeSeedKeys = alternativeSeedKeys
    }
}

/// One routine a program installs. `seedKey` is both the installed routine's
/// stable identity (`Routine.seedKey`) and its display-name localization key.
struct RoutineProgramRoutine: Sendable, Equatable, Identifiable {
    let seedKey: String
    /// Days after the program's first workout that this routine is first due.
    let startOffsetDays: Int
    let exercises: [RoutineProgramExercise]

    var id: String { seedKey }
}

struct RoutineProgram: Sendable, Equatable, Identifiable {
    /// Short identifier, e.g. "full_body" — also the stem of the program's
    /// `routine_programs.<id>.*` copy keys.
    let id: String
    /// The every-N-days cadence each routine gets when the user plans by
    /// recovery time. Never a weekday plan (docs/monetization-strategy.md P9).
    let cadenceDays: Int
    let routines: [RoutineProgramRoutine]
}
