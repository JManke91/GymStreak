//
//  RoutineProgramCatalog+Fighter.swift
//  GymStreak
//
//  Fighter Strength as data. Content source of truth:
//  docs/research/routine-programs-fighter-strength.md §3 (signed off 2026-09-27).
//  See docs/routine-programs.md.
//

import Foundation

extension RoutineProgramCatalog {

    /// Kostikiadis et al. 2018 (MMA) compressed to two lifting sessions: A and B
    /// each every 7 days, B three days after A. Power lifts, jumps and throws
    /// carry no rep-range goal, so the app never suggests more weight for them.
    /// Lifting only — conditioning stays in the fight-conditioning program.
    static let fighterStrength = RoutineProgram(
        id: "fighter",
        cadenceDays: 7,
        routines: [
            RoutineProgramRoutine(
                seedKey: "seed.program.fighter.a",
                startOffsetDays: 0,
                exercises: [
                    RoutineProgramExercise(
                        "seed.exercise.box_jump", sets: 3, fixedReps: 3, rest: 90,
                        note: "routine_programs.note.power_step_down"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.barbell_back_squat", sets: 4, reps: 3...5, rest: 180,
                        alternatives: ["seed.exercise.front_squat"],
                        note: "routine_programs.note.main_lift"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.barbell_bench_press", sets: 4, reps: 3...5, rest: 180, superset: "contrast",
                        alternatives: ["seed.exercise.dumbbell_bench_press"],
                        note: "routine_programs.note.main_lift"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.medicine_ball_chest_pass", sets: 4, fixedReps: 3, rest: 180, superset: "contrast"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.pull_up", sets: 3, reps: 4...6, rest: 150,
                        alternatives: ["seed.exercise.lat_pulldown"],
                        note: "routine_programs.note.weighted"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.bulgarian_split_squat", sets: 2, reps: 6...8, rest: 120,
                        note: "routine_programs.note.per_leg"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.ab_wheel_rollout", sets: 3, reps: 6...10, rest: 90,
                        note: "routine_programs.note.trunk"
                    ),
                ]
            ),
            RoutineProgramRoutine(
                seedKey: "seed.program.fighter.b",
                startOffsetDays: 3,
                exercises: [
                    RoutineProgramExercise(
                        "seed.exercise.jump_shrug", sets: 4, fixedReps: 3, rest: 150,
                        alternatives: ["seed.exercise.hang_power_clean"],
                        note: "routine_programs.note.power"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.deadlift", sets: 3, reps: 3...5, rest: 180,
                        note: "routine_programs.note.main_lift"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.overhead_press", sets: 3, reps: 4...6, rest: 150,
                        alternatives: ["seed.exercise.seated_dumbbell_shoulder_press"]
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.pendlay_row", sets: 3, reps: 5...6, rest: 150,
                        alternatives: ["seed.exercise.barbell_row"],
                        note: "routine_programs.note.explosive_row"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.medicine_ball_rotational_throw", sets: 3, fixedReps: 3, rest: 90,
                        note: "routine_programs.note.power_per_side"
                    ),
                    RoutineProgramExercise(
                        "seed.exercise.hanging_leg_raise", sets: 3, reps: 8...12, rest: 90,
                        alternatives: ["seed.exercise.cable_crunch"],
                        note: "routine_programs.note.trunk"
                    ),
                ]
            ),
        ],
        alternativeHintKey: nil,
        guidanceRuleKeys: ["lift_first", "sparring", "fast", "strength"],
        sourceKeys: ["kostikiadis", "nsca"],
        guidanceTitleKey: "routine_programs.fighter.guidance_title",
        warningRuleKeys: ["sparring"],
        phaseKeys: ["strength", "maintain", "power", "taper"],
        pairsWithConditioning: true
    )
}
