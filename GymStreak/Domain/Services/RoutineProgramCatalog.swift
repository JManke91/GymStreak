//
//  RoutineProgramCatalog.swift
//  GymStreak
//
//  The ready-made programs as data. Content source of truth:
//  docs/research/routine-programs-hypertrophy.md §3 (signed off 2026-09-27).
//  See docs/routine-programs.md.
//

import Foundation

enum RoutineProgramCatalog {

    static let programs: [RoutineProgram] = [beginnerFullBody]

    static func program(withId id: String) -> RoutineProgram? {
        programs.first { $0.id == id }
    }

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
        sourceKeys: ["basic_beginner", "acsm", "meta_analyses"]
    )
}
