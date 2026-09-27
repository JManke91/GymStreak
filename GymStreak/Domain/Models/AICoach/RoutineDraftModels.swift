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

/// One thing a draft lacks before it is worth reviewing — asked about one at a time, and
/// decided by `GroundedRoutineDraft.gaps`, never by the model.
enum RoutineDraftGap: Equatable, Sendable {
    /// The draft names no exercise at all.
    case exercises
    /// These exercises, by their drafted names, have no stated set count.
    case setCounts(exerciseNames: [String])
    /// The description gave the workout no name.
    case name
}

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
    /// The set count Create writes — the stated one, or the Swift default when the
    /// description gave none (`isSetCountStated` says which).
    let setCount: Int
    /// Whether the person actually said how many sets. `false` means `setCount` is the
    /// Swift default, which is a gap to ask about before review rather than a value the
    /// person chose.
    let isSetCountStated: Bool
    let reps: Int
    /// Canonical kilograms, like every other stored weight in the app. Zero means the
    /// exercise is drafted without a load, not that a load is missing.
    let weightKilograms: Double
    /// The rep-range goal the person stated, or `nil`/`nil` — **no goal is the ordinary
    /// case**, never something to fill in. Both set or both nil, like
    /// `RoutineExercise.hasRepRangeGoal` expects.
    let targetRepMin: Int?
    let targetRepMax: Int?
    /// The rest between sets for every set of this exercise — the stated one, or the
    /// Swift default.
    let restTime: TimeInterval

    init(
        id: UUID = UUID(),
        draftedName: String,
        match: Match,
        setCount: Int,
        isSetCountStated: Bool = true,
        reps: Int,
        weightKilograms: Double,
        targetRepMin: Int? = nil,
        targetRepMax: Int? = nil,
        restTime: TimeInterval = RoutineDraftGrounder.defaultRestTime
    ) {
        self.id = id
        self.draftedName = draftedName
        self.match = match
        self.setCount = setCount
        self.isSetCountStated = isSetCountStated
        self.reps = reps
        self.weightKilograms = weightKilograms
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.restTime = restTime
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
            isSetCountStated: isSetCountStated,
            reps: reps,
            weightKilograms: weightKilograms,
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            restTime: restTime
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

    /// Empty when the description gave the workout no name. Settable because a name the
    /// person gives in answer to the question is applied here, in Swift.
    var name: String
    /// Everything drafted, resolved or not, in the order the description gave.
    private(set) var exercises: [GroundedDraftExercise]
    /// Names the model wrote that the person never said — dropped by the grounding pass,
    /// and listed so the sheet can say so rather than lose them silently.
    let droppedNames: [String]

    init(name: String, exercises: [GroundedDraftExercise], droppedNames: [String] = []) {
        self.name = name
        self.exercises = exercises
        self.droppedNames = droppedNames
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

    /// What the draft still lacks before it is worth reviewing, in the order to ask about
    /// it — empty when it is complete. **This is the completeness predicate, and it is
    /// Swift's, never the model's:** a prompt rule asking the model whether it has enough
    /// is a request, this is a guarantee.
    ///
    /// No exercises makes every other gap moot, so it is then the only one. The order
    /// after it puts the most useful answer first, so a person who stops answering early
    /// is left with the most useful draft.
    var gaps: [RoutineDraftGap] {
        guard !exercises.isEmpty else { return [.exercises] }
        var gaps: [RoutineDraftGap] = []
        let unstated = exercises.filter { !$0.isSetCountStated }.map(\.draftedName)
        if !unstated.isEmpty { gaps.append(.setCounts(exerciseNames: unstated)) }
        if name.isEmpty { gaps.append(.name) }
        return gaps
    }

    var isComplete: Bool { gaps.isEmpty }

    /// Points one still-unresolved row at a library exercise, keeping its position and
    /// its drafted figures.
    ///
    /// Deliberately a no-op on an already-resolved row: swapping an exercise the library
    /// *did* place would be re-drafting it, not correcting a name the library could not
    /// read.
    mutating func resolve(_ id: UUID, to exercise: Exercise) {
        guard let index = exercises.firstIndex(where: { $0.id == id }),
              !exercises[index].isResolved
        else { return }
        exercises[index] = exercises[index].pointed(at: exercise)
    }

    /// Drops one row, resolved or not.
    mutating func remove(_ id: UUID) {
        exercises.removeAll { $0.id == id }
    }

    /// Moves one row `offset` places up (negative) or down (positive), clamped to the
    /// list. Position in this array is what `pendingExercises()` turns into
    /// `RoutineExercise.order`, so moving here is what reorders the saved routine.
    mutating func move(_ id: UUID, by offset: Int) {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(index + offset, 0), exercises.count - 1)
        guard target != index else { return }
        exercises.insert(exercises.remove(at: index), at: target)
    }
}
