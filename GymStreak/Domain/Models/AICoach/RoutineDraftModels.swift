//
//  RoutineDraftModels.swift
//  GymStreak
//
//  The routine-drafting value types: what the model produced (`RoutineDraftSnapshot`)
//  and what Swift decided (`GroundedRoutineDraft`). See docs/ai-coach-routine-drafting.md.
//
//  Deliberately plain Foundation, with no FoundationModels import: the `@Generable`
//  schema lives in `RoutineDraftOutput.swift`, and `Data/` maps a streaming snapshot of
//  it into the types here. That is what keeps the drafting protocol, the grounding pass
//  and the ViewModel free of a framework type that cannot be constructed in a test
//  process — `LanguageModelSession.ResponseStream` has no public initializer.
//

import Foundation

// MARK: - What the model produced

/// One exercise as the model wrote it: a free-text name plus three raw numbers.
///
/// Nothing here is trusted. The name is the model's spelling of whatever the person
/// typed and has not met the exercise library yet; the numbers are still in the
/// **reader's display unit** and still carry the "the description did not say" sentinel.
/// `RoutineDraftGrounder` is what turns this into something the app may write.
struct RoutineDraftEntry: Equatable, Sendable {

    let name: String
    /// How many sets, or `RoutineDraftGrounder.unstatedNumber` when the description
    /// gave none. There is no optional here on purpose: a `@Generable` optional has
    /// already produced the literal string "nil" in rendered output in this app, so
    /// absence is carried by a sentinel and decided in Swift (docs/ai-coach.md).
    let setCount: Int
    /// Repetitions per set, with the same sentinel.
    let reps: Int
    /// The load for one set **in the reader's display unit**, with the same sentinel.
    /// Converted to canonical kilograms by the grounding pass, never before.
    let weight: Double

    init(name: String, setCount: Int, reps: Int, weight: Double) {
        self.name = name
        self.setCount = setCount
        self.reps = reps
        self.weight = weight
    }
}

/// One streaming snapshot of a routine draft: the name so far, and the exercises that
/// are **fully generated**.
///
/// Partially generated exercises are dropped by the mapping in `Data/`, not carried
/// here half-filled. A name being assembled token by token would otherwise be resolved
/// against the library on every snapshot, and a row would flicker through whatever
/// "Ben", "Bench", "Bench pr" happen to match before settling.
struct RoutineDraftSnapshot: Equatable, Sendable {

    let name: String
    let exercises: [RoutineDraftEntry]

    init(name: String, exercises: [RoutineDraftEntry]) {
        self.name = name
        self.exercises = exercises
    }
}

// MARK: - What Swift decided

/// One drafted exercise after grounding: a **real library `Exercise`**, a set count and
/// a rep count inside the app's own bounds, and a weight in canonical kilograms.
///
/// Holding the `Exercise` rather than a name is the whole point of the grounding pass —
/// it is what `RoutinesViewModel.createRoutine(name:pendingExercises:)` needs, and it is
/// why the review sheet can show the library's own spelling instead of the model's.
struct GroundedDraftExercise: Identifiable {

    let id = UUID()
    let exercise: Exercise
    let setCount: Int
    let reps: Int
    /// Canonical kilograms, like every other stored weight in the app. Zero means the
    /// exercise is drafted without a load, not that a load is missing.
    let weightKilograms: Double

    init(exercise: Exercise, setCount: Int, reps: Int, weightKilograms: Double) {
        self.exercise = exercise
        self.setCount = setCount
        self.reps = reps
        self.weightKilograms = weightKilograms
    }
}

/// A draft that has met the live exercise library: what can be created, and what was
/// left out.
///
/// `unmatchedNames` is never empty-by-omission. An exercise the resolver cannot place is
/// excluded from `exercises` **and** named here, because the one thing this surface may
/// never do is quietly drop something the person asked for — or invent a library entry
/// to hold it. Ticket 02 makes these resolvable; until then the sheet says so out loud.
struct GroundedRoutineDraft {

    let name: String
    let exercises: [GroundedDraftExercise]
    let unmatchedNames: [String]

    init(name: String, exercises: [GroundedDraftExercise], unmatchedNames: [String]) {
        self.name = name
        self.exercises = exercises
        self.unmatchedNames = unmatchedNames
    }

    /// `true` when there is nothing the person could create — the state the sheet has to
    /// explain rather than offer a Create button for.
    var hasNothingToCreate: Bool { exercises.isEmpty }
}
