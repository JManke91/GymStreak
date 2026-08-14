//
//  PreviousPerformanceLookup.swift
//  GymStreak
//

import Foundation

/// The value-typed request the "compare against last time" read boundary takes.
///
/// Audit P1.6: the comparison used to run entirely on the main actor because it took a
/// caller-supplied main-context `WorkoutSession` and issued one unbounded
/// `FetchDescriptor<WorkoutSession>` **per exercise**. A `@ModelActor` cannot accept a
/// main-context `@Model`, so the workout's identity crosses as this immutable
/// description instead: every field is a value the main actor already holds, and nothing
/// in it can fault a relationship on the other side.
///
/// **Deliberately not a session id to re-fetch.** Passing `WorkoutSession.id` and
/// re-fetching inside the actor would bet on the workout already being visible to a
/// second `ModelContext`. SwiftData does not document whether one context sees another's
/// unsaved changes — an Apple DTS engineer declined to confirm either behaviour on
/// forum thread 763487 — and the save sheet compares a workout the user has not
/// committed yet. The failure mode would be a silently empty comparison, i.e. every
/// exercise falsely badged "new", not an error. See `docs/progress-charts.md`.
struct PreviousPerformanceLookup: Sendable {

    /// Only sessions strictly before this instant are candidates. The workout being
    /// compared is excluded by its own start time, exactly as the replaced predicate did.
    let before: Date

    /// The routine the workout was performed from, if it still exists. Occurrence-index
    /// matching is only meaningful inside a proven routine context.
    let routineId: UUID?

    /// One entry per exercise in the workout, ordered by `WorkoutExercise.order`.
    let exercises: [Query]

    /// One exercise of the workout being compared, reduced to the fields that decide
    /// which historical `WorkoutExercise` is its predecessor.
    struct Query: Sendable {
        /// `WorkoutExercise.id` — the key the resolved performance comes back under.
        let workoutExerciseId: UUID
        let exerciseName: String
        let exerciseId: UUID?
        let loadBehavior: ExerciseLoadBehavior
        /// The routine slot this exercise was performed from, when the workout was
        /// recorded after slot ids were snapshotted. The strongest identity available.
        let routineExerciseId: UUID?
    }
}
