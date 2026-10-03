//
//  RoutineProgramCatalog.swift
//  GymStreak
//
//  The ready-made programs as data. Content source of truth:
//  docs/research/routine-programs-hypertrophy.md §3 and §4 (signed off 2026-09-27);
//  Fighter Strength lives in RoutineProgramCatalog+Fighter.swift.
//  See docs/routine-programs.md.
//

import Foundation

enum RoutineProgramCatalog {

    static let programs: [RoutineProgram] = [beginnerFullBody, pushPullLegs, fighterStrength]

    static func program(withId id: String) -> RoutineProgram? {
        programs.first { $0.id == id }
    }

    /// The program an installed routine belongs to, by its `Routine.seedKey`.
    /// Nil for the user's own routines (`""`) and the example routine.
    static func program(forRoutineSeedKey seedKey: String) -> RoutineProgram? {
        programsByRoutineSeedKey[seedKey]
    }

    private static let programsByRoutineSeedKey: [String: RoutineProgram] = Dictionary(
        uniqueKeysWithValues: programs.flatMap { program in
            program.routines.map { ($0.seedKey, program) }
        }
    )

    /// r/Fitness Basic Beginner Routine + ACSM novice rep ranges. A and B each
    /// every 4 days, B two days after A → strict A-rest-B-rest alternation.
    static let beginnerFullBody = RoutineProgram(
        id: "full_body",
        cadenceDays: 4,
        routines: [
            RoutineProgramRoutine(
                seedKey: "seed.program.full_body.a",
                startOffsetDays: 0,
                exercises: [
                    RoutineProgramExercise(
                        "seed.exercise.barbell_back_squat", sets: 3, reps: 8...12, rest: 180,
                        alternatives: ["seed.exercise.leg_press", "seed.exercise.goblet_squat"]
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.barbell_bench_press", sets: 3, reps: 8...12, rest: 150,
                        alternatives: ["seed.exercise.machine_chest_press", "seed.exercise.dumbbell_bench_press"]
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.lat_pulldown", sets: 3, reps: 8...12, rest: 120,
                        note: "routine_programs.note.vertical_pull"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.lying_leg_curl", sets: 2, reps: 10...15, rest: 90,
                        note: "routine_programs.note.hamstrings"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.dumbbell_lateral_raise", sets: 2, reps: 12...20, rest: 60, superset: "arms"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.tricep_pushdown", sets: 2, reps: 10...15, rest: 60, superset: "arms"
                    ),
                ]
            ),
            RoutineProgramRoutine(
                seedKey: "seed.program.full_body.b",
                startOffsetDays: 2,
                exercises: [
                    RoutineProgramExercise(
                        "seed.exercise.romanian_deadlift", sets: 3, reps: 8...12, rest: 180,
                        note: "routine_programs.note.hip_hinge"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.overhead_press", sets: 3, reps: 8...12, rest: 150,
                        alternatives: ["seed.exercise.machine_shoulder_press", "seed.exercise.seated_dumbbell_shoulder_press"]
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.seated_cable_row", sets: 3, reps: 8...12, rest: 120,
                        note: "routine_programs.note.horizontal_pull"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.leg_press", sets: 3, reps: 10...15, rest: 120,
                        note: "routine_programs.note.second_leg_exercise"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.incline_dumbbell_bench_press", sets: 2, reps: 8...12, rest: 120,
                        note: "routine_programs.note.upper_chest"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.dumbbell_curl", sets: 2, reps: 10...15, rest: 60,
                        note: "routine_programs.note.biceps"
                    ),
                ]
            ),
        ],
        alternativeHintKey: "routine_programs.detail.alternative_tip",
        guidanceRuleKeys: ["effort", "start_weight", "progression", "deload", "graduation"],
        sourceKeys: ["basic_beginner", "acsm", "meta_analyses"],
        ruleLinks: ["graduation": "ppl"],
        showsLengthStat: true
    )

    /// Metallicadpa's PPL exercises on double progression, run as the rotating
    /// 5-day split: each routine every 5 days, offsets 0/1/3 →
    /// Push · Pull · rest · Legs · rest (~4 sessions a week, rest days built in).
    static let pushPullLegs = RoutineProgram(
        id: "ppl",
        cadenceDays: 5,
        routines: [
            RoutineProgramRoutine(
                seedKey: "seed.program.ppl.push",
                startOffsetDays: 0,
                exercises: [
                    RoutineProgramExercise(
                        "seed.exercise.barbell_bench_press", sets: 4, reps: 6...10, rest: 180,
                        note: "routine_programs.note.main_lift"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.overhead_press", sets: 3, reps: 8...12, rest: 150,
                        note: "routine_programs.note.shoulders"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.incline_dumbbell_bench_press", sets: 3, reps: 8...12, rest: 120,
                        note: "routine_programs.note.upper_chest"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.tricep_pushdown", sets: 3, reps: 8...12, rest: 60, superset: "pushdown"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.dumbbell_lateral_raise", sets: 3, reps: 15...20, rest: 60, superset: "pushdown"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.overhead_tricep_extension", sets: 3, reps: 8...12, rest: 60, superset: "extension"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.cable_lateral_raise", sets: 3, reps: 15...20, rest: 60, superset: "extension"
                    ),
                ]
            ),
            RoutineProgramRoutine(
                seedKey: "seed.program.ppl.pull",
                startOffsetDays: 1,
                exercises: [
                    RoutineProgramExercise(
                        "seed.exercise.deadlift", sets: 2, reps: 4...6, rest: 180,
                        note: "routine_programs.note.heavy_hinge"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.barbell_row", sets: 3, reps: 6...10, rest: 150,
                        note: "routine_programs.note.main_lift"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.lat_pulldown", sets: 3, reps: 8...12, rest: 120,
                        alternatives: ["seed.exercise.pull_up", "seed.exercise.assisted_pull_up"]
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.seated_cable_row", sets: 3, reps: 8...12, rest: 120,
                        note: "routine_programs.note.horizontal_pull"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.face_pull", sets: 5, reps: 15...20, rest: 60,
                        note: "routine_programs.note.rear_delts"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.hammer_curl", sets: 4, reps: 8...12, rest: 60,
                        note: "routine_programs.note.biceps"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.dumbbell_curl", sets: 4, reps: 8...12, rest: 60,
                        note: "routine_programs.note.biceps"
                    ),
                ]
            ),
            RoutineProgramRoutine(
                seedKey: "seed.program.ppl.legs",
                startOffsetDays: 3,
                exercises: [
                    RoutineProgramExercise(
                        "seed.exercise.barbell_back_squat", sets: 3, reps: 6...10, rest: 180,
                        note: "routine_programs.note.main_lift"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.romanian_deadlift", sets: 3, reps: 8...12, rest: 150,
                        note: "routine_programs.note.hip_hinge"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.leg_press", sets: 3, reps: 8...12, rest: 120,
                        note: "routine_programs.note.quads"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.lying_leg_curl", sets: 3, reps: 8...12, rest: 90,
                        note: "routine_programs.note.hamstrings"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.standing_calf_raise", sets: 5, reps: 8...12, rest: 60,
                        note: "routine_programs.note.calves"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.cable_crunch", sets: 3, reps: 10...15, rest: 60,
                        note: "routine_programs.note.optional_abs"
                    ),
                ]
            ),
        ],
        alternativeHintKey: nil,
        guidanceRuleKeys: ["effort", "start_weight", "progression", "deload"],
        sourceKeys: ["metallicadpa", "meta_analyses"]
    )
}
