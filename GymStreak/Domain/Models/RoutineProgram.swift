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
    /// Reps every set starts at: the bottom of the rep range, or the fixed count
    /// of a slot without one.
    let startReps: Int
    /// Rep-range goal. Nil for power lifts, jumps and throws, which progress by
    /// speed rather than reps, so the app never suggests a weight increase.
    let repMin: Int?
    let repMax: Int?
    let restTime: TimeInterval
    /// Slots sharing a non-nil group are performed as a superset, in order.
    let supersetGroup: String?
    /// Swap-in exercises, already set up with the primary's scheme.
    let alternativeSeedKeys: [String]
    /// Localization key of the one-line role shown on the detail screen
    /// ("Vertical pull"), shown before the alternatives when there are any.
    /// A superset partner note replaces it on a slot without alternatives.
    let noteKey: String?

    init(
        _ exerciseSeedKey: String,
        sets setCount: Int,
        reps: ClosedRange<Int>,
        rest restTime: TimeInterval,
        superset supersetGroup: String? = nil,
        alternatives alternativeSeedKeys: [String] = [],
        note noteKey: String? = nil
    ) {
        self.exerciseSeedKey = exerciseSeedKey
        self.setCount = setCount
        self.startReps = reps.lowerBound
        self.repMin = reps.lowerBound
        self.repMax = reps.upperBound
        self.restTime = restTime
        self.supersetGroup = supersetGroup
        self.alternativeSeedKeys = alternativeSeedKeys
        self.noteKey = noteKey
    }

    /// A slot with a fixed rep count and no rep-range goal (Fighter Strength's
    /// power lifts, jumps and throws).
    init(
        _ exerciseSeedKey: String,
        sets setCount: Int,
        fixedReps: Int,
        rest restTime: TimeInterval,
        superset supersetGroup: String? = nil,
        alternatives alternativeSeedKeys: [String] = [],
        note noteKey: String? = nil
    ) {
        self.exerciseSeedKey = exerciseSeedKey
        self.setCount = setCount
        self.startReps = fixedReps
        self.repMin = nil
        self.repMax = nil
        self.restTime = restTime
        self.supersetGroup = supersetGroup
        self.alternativeSeedKeys = alternativeSeedKeys
        self.noteKey = noteKey
    }
}

/// One routine a program installs. `seedKey` is both the installed routine's
/// stable identity (`Routine.seedKey`) and its display-name localization key;
/// `<seedKey>.short` is its letter on the detail screen's timeline ("A").
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
    /// Key of the barbell → alternative hint on the detail screen; nil omits it.
    let alternativeHintKey: String?
    /// Stems of the "How to train it" rules, in order:
    /// `routine_programs.<id>.rule.<stem>.title|detail`.
    let guidanceRuleKeys: [String]
    /// Stems of the "Based on" sources, in order:
    /// `routine_programs.<id>.source.<stem>.name|role`.
    let sourceKeys: [String]
    /// Rules that point to another program, by rule stem → program id
    /// (Full Body's graduation rule → Push / Pull / Legs).
    var ruleLinks: [String: String] = [:]
    /// The detail's third stat is the program's length ("~12 wk", `stat.length`)
    /// instead of the session length (`stat.duration`).
    var showsLengthStat = false
    /// The guidance section's heading ("How to train it").
    var guidanceTitleKey = "routine_programs.detail.how_to_train"
    /// Guidance rules shown as a warning ("!" in the warning colour) instead of
    /// a number (Fighter Strength's "Not before hard sparring").
    var warningRuleKeys: Set<String> = []
    /// Stems of the "Fight camp" phases, in order:
    /// `routine_programs.<id>.phase.<stem>.weeks|title|detail`. Text only.
    var phaseKeys: [String] = []
    /// The detail links to the fight-conditioning program (lifting-only plans).
    var pairsWithConditioning = false
}
