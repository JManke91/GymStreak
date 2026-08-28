//
//  ExerciseDeepDiveAggregate.swift
//  GymStreak
//

import Foundation

/// Everything one deep-dive generation needs from workout history, as values.
///
/// The two halves travel together because one walk of the session graph answers both,
/// and because they have to agree: the narrative describes a body of work, and the
/// timestamp is what tells a later run whether that body of work has changed. Answering
/// them from two separate fetches is the only way they could ever disagree — and it is
/// what the deep-dive did before ticket 02, twice over and on the main actor.
///
/// Nothing here is a `PersistentModel`, which is what lets it cross off the model actor
/// that built it.
struct ExerciseDeepDiveAggregate: Sendable {
    /// The most recent session holding a completed set of the described usage, or `nil`
    /// when there is none. `ExerciseDeepDiveViewModel` stamps its cache key with it.
    let lastCompletedSetTimestamp: Date?

    /// The prompt input, or `nil` when the described usage has too little history for a
    /// narrative (fewer than 4 completed sets, or fewer than two sessions).
    let input: ExerciseDeepDiveInput?
}
