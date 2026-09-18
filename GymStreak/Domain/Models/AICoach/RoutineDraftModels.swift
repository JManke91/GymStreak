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

/// One drafted exercise after grounding: the name the person used, how the live library
/// answered it, and figures inside the app's own bounds.
///
/// It carries the drafted name **whether or not the library could place it**. That is
/// what lets an unresolvable exercise stay on screen as something the person can point
/// at a real library entry — see `Match` — instead of being reduced to a line of text
/// saying it was dropped.
struct GroundedDraftExercise: Identifiable {

    /// How the live library answered the drafted name.
    ///
    /// The two failing cases are kept apart on purpose. `.ambiguous` knows a short,
    /// correct list of library exercises the name could mean and can offer it; `.unmatched`
    /// knows nothing and can only offer the whole library. Collapsing them would throw
    /// away the one thing that makes the ambiguous case answerable in a tap.
    enum Match {
        /// A library exercise this draft may claim.
        case resolved(Exercise)
        /// Several **distinct** library names matched equally well. The candidates, in
        /// the order the resolver ranked them, to be offered before the full library.
        case ambiguous([Exercise])
        /// Nothing in the library matched. The person picks from the whole of it.
        case unmatched
    }

    let id: UUID
    /// What the person said, as the model transcribed it. Kept after resolution too: a
    /// row that has been pointed at a library exercise still came from these words, and
    /// the picker names them.
    let draftedName: String
    let match: Match
    let setCount: Int
    let reps: Int
    /// Canonical kilograms, like every other stored weight in the app. Zero means the
    /// exercise is drafted without a load, not that a load is missing.
    let weightKilograms: Double

    init(
        id: UUID = UUID(),
        draftedName: String,
        match: Match,
        setCount: Int,
        reps: Int,
        weightKilograms: Double
    ) {
        self.id = id
        self.draftedName = draftedName
        self.match = match
        self.setCount = setCount
        self.reps = reps
        self.weightKilograms = weightKilograms
    }

    /// The library exercise this draft may write, or `nil` while it is still unresolved.
    var exercise: Exercise? {
        if case .resolved(let exercise) = match { return exercise }
        return nil
    }

    var isResolved: Bool { exercise != nil }

    /// Library exercises to offer **before** the full library. Empty for `.unmatched`,
    /// which is precisely the case that has nothing better to offer.
    var candidates: [Exercise] {
        if case .ambiguous(let candidates) = match { return candidates }
        return []
    }

    /// The same drafted exercise pointed at a library exercise — same identity, same
    /// position, same figures. Resolving a name corrects the machine's reading of it; it
    /// does not re-draft the exercise.
    func pointed(at exercise: Exercise) -> GroundedDraftExercise {
        GroundedDraftExercise(
            id: id,
            draftedName: draftedName,
            match: .resolved(exercise),
            setCount: setCount,
            reps: reps,
            weightKilograms: weightKilograms
        )
    }
}

/// A draft that has met the live exercise library: everything the person described, in
/// the order they described it, each either resolved to a library exercise or still
/// waiting for them to say which one it is.
///
/// Unresolved exercises are **kept in the draft, in place** — never silently dropped and
/// never invented into the library. They are excluded from what Create writes (see
/// `resolvedExercises`), and the sheet says so; resolving one in place is what keeps the
/// described order the routine's order.
struct GroundedRoutineDraft {

    let name: String
    /// Everything drafted, resolved or not, in the order the description gave.
    private(set) var exercises: [GroundedDraftExercise]

    init(name: String, exercises: [GroundedDraftExercise]) {
        self.name = name
        self.exercises = exercises
    }

    /// The exercises a Create may actually write. **This is the only list that reaches
    /// the store** — an unresolved row can never become a saved exercise.
    ///
    /// Its complement is not de-duplicated, deliberately: two descriptions of the same
    /// unknown movement are two pieces of work with their own figures, and each gets its
    /// own row to answer.
    var resolvedExercises: [GroundedDraftExercise] {
        exercises.filter(\.isResolved)
    }

    /// `true` when there is nothing the person could create — the state the sheet has to
    /// explain rather than offer a Create button for.
    var hasNothingToCreate: Bool { resolvedExercises.isEmpty }

    /// `true` while at least one row still has to be pointed at a library exercise or
    /// removed. What the sheet turns into the "these are left out" note.
    var hasUnresolvedExercises: Bool { exercises.contains { !$0.isResolved } }

    /// Points one still-unresolved row at a library exercise, keeping its position and
    /// its drafted figures.
    ///
    /// Deliberately a no-op on an already-resolved row: swapping an exercise the library
    /// *did* place is editing the draft, which is ticket 03, not correcting a name the
    /// library could not read.
    mutating func resolve(_ id: UUID, to exercise: Exercise) {
        guard let index = exercises.firstIndex(where: { $0.id == id }),
              !exercises[index].isResolved
        else { return }
        exercises[index] = exercises[index].pointed(at: exercise)
    }

    /// Drops one still-unresolved row. Removing a *resolved* exercise is ticket 03.
    mutating func removeUnresolved(_ id: UUID) {
        exercises.removeAll { $0.id == id && !$0.isResolved }
    }
}
