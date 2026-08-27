//
//  SeedRoutineCatalog.swift
//  GymStreak
//
//  The content of the built-in example routine a user with no routines of
//  their own finds waiting on the Routines tab. See
//  docs/example-starter-routine.md.
//

import Foundation

/// One exercise slot of a built-in example routine.
///
/// `exerciseSeedKey` points at a `SeedExerciseCatalog` row rather than carrying
/// its own exercise: the example routine uses the same library the user does,
/// and a slot whose exercise the user deleted is simply dropped (never
/// resurrected).
struct SeedRoutineExercise {
    let exerciseSeedKey: String
    let setCount: Int
    /// Starting rep count for every set. With a rep range it is the lower
    /// bound, so the routine starts at the bottom of its own goal.
    let reps: Int
    let targetRepMin: Int?
    let targetRepMax: Int?
    let restTime: TimeInterval
    /// Slots sharing a non-nil group are performed as a superset, in the order
    /// they appear in `SeedRoutine.exercises`. A group left with fewer than two
    /// resolvable slots collapses to standalone exercises.
    let supersetGroup: String?

    init(
        exerciseSeedKey: String,
        setCount: Int,
        reps: Int,
        targetRepMin: Int? = nil,
        targetRepMax: Int? = nil,
        restTime: TimeInterval,
        supersetGroup: String? = nil
    ) {
        self.exerciseSeedKey = exerciseSeedKey
        self.setCount = setCount
        self.reps = reps
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.restTime = restTime
        self.supersetGroup = supersetGroup
    }
}

/// One built-in routine. `seedKey` is both its stable cross-device identity and
/// its `Localizable.strings` key for the display name — the same convention
/// `SeedExercise` uses.
struct SeedRoutine {
    let seedKey: String
    let exercises: [SeedRoutineExercise]
    /// Below this many resolvable exercises the routine is not seeded at all.
    /// A two-exercise stump is a worse first impression than the empty state it
    /// replaces, and the seeder retries on a later launch rather than stamping
    /// the version — so a device whose library arrives late still gets it.
    let minimumResolvedExercises: Int
}

/// The built-in example routine catalog.
///
/// Unlike `SeedExerciseCatalog` there is no per-row `introducedInVersion`:
/// seeding is gated on the store holding **zero** routines, so a second entry
/// added later could never reach a user who kept the first one. Adding one
/// means rethinking that gate, not appending a row.
enum SeedRoutineCatalog {
    static let currentVersion = 1

    /// One full-body session, picked so that the three features a new user
    /// cannot otherwise discover — rep-range goals, supersets, per-exercise
    /// rest — each show up at least once.
    ///
    /// Weights are 0: the user's own loads are unknowable and a fake number
    /// would poison their first progress chart. The plank carries one rep per
    /// set (the app has no time-based sets) and no rep range.
    static let entries: [SeedRoutine] = [
        SeedRoutine(
            seedKey: "seed.routine.full_body_starter",
            exercises: [
                SeedRoutineExercise(
                    exerciseSeedKey: "seed.exercise.barbell_back_squat",
                    setCount: 3, reps: 8, targetRepMin: 8, targetRepMax: 12, restTime: 150
                ),
                SeedRoutineExercise(
                    exerciseSeedKey: "seed.exercise.barbell_bench_press",
                    setCount: 3, reps: 8, targetRepMin: 8, targetRepMax: 12, restTime: 120
                ),
                SeedRoutineExercise(
                    exerciseSeedKey: "seed.exercise.lat_pulldown",
                    setCount: 3, reps: 10, targetRepMin: 10, targetRepMax: 12, restTime: 90
                ),
                SeedRoutineExercise(
                    exerciseSeedKey: "seed.exercise.dumbbell_curl",
                    setCount: 3, reps: 10, targetRepMin: 10, targetRepMax: 15, restTime: 60,
                    supersetGroup: "arms"
                ),
                SeedRoutineExercise(
                    exerciseSeedKey: "seed.exercise.tricep_pushdown",
                    setCount: 3, reps: 10, targetRepMin: 10, targetRepMax: 15, restTime: 60,
                    supersetGroup: "arms"
                ),
                SeedRoutineExercise(
                    exerciseSeedKey: "seed.exercise.plank",
                    setCount: 3, reps: 1, restTime: 60
                ),
            ],
            minimumResolvedExercises: 4
        )
    ]
}
