//
//  AppliedOverloadCorrelationReading.swift
//  GymStreak
//
//  Progressive-overload resurface, ticket 05.
//
//  When the user raises a working weight from the Watch's post-workout recap,
//  the increase travels as a template-only transaction — it never amends the
//  frozen completed workout. History therefore has no way to know the increase
//  happened, and would keep offering it.
//
//  This is that missing link, and nothing more: a read of which routine slots
//  of a recorded workout already had an increase applied, and to what weight.
//  The recorded workout itself stays untouched, so every performed value,
//  volume figure and chart point is exactly what the user did.
//

import Foundation

/// One increase already applied to the live routine template.
struct AppliedOverloadRecord: Equatable, Sendable {
    /// The new template weight, or nil when the target's sets do not all share
    /// one — a pyramid or drop scheme, where naming the first set's result
    /// would misstate every other set. Callers must then show the applied state
    /// WITHOUT a number rather than picking one.
    let newWeight: Double?
}

protocol AppliedOverloadCorrelationReading: AnyObject, Sendable {
    /// Increases already applied from a recorded workout, keyed by routine slot
    /// (`WorkoutExercise.routineExerciseId`). Empty when none — including for
    /// workouts recorded before this existed, which stay ordinarily eligible.
    ///
    /// `async` because it reads from disk: callers are on a view's load path,
    /// and the main thread must not do the read.
    func appliedOverloads(forWorkout workoutID: UUID) async -> [UUID: AppliedOverloadRecord]
}
