//
//  RoutineDraftGrounder.swift
//  GymStreak
//
//  Turns what the model wrote into something the app may write: every exercise name
//  resolved against the live library, every number inside the app's own bounds, every
//  weight in canonical kilograms. See docs/ai-coach-routine-drafting.md.
//
//  Pure logic over already-fetched `Exercise` models, so it lives in `Domain/` and stays
//  isolation-agnostic — the same arrangement as `ExerciseNameResolver`, which it wraps.
//

import Foundation

/// The Swift half of "the model drafts; Swift decides and writes."
///
/// It is the only thing standing between a free-text name the model produced and a
/// routine the person keeps, and it has exactly two jobs:
///
/// 1. **Resolve every name against the live library.** Not "look it up if convenient" —
///    an exercise that does not resolve is carried as unresolved and answered by the
///    person, never created, never guessed at. This app does not invent library entries
///    on the model's word.
/// 2. **Bound every number.** The model's figures are copied from a sentence a person
///    typed, so they can be absent (the sentinel), absurd, or negative.
final class RoutineDraftGrounder {

    // MARK: - Tuning

    /// What the schema asks the model to write when the description gives no figure.
    ///
    /// Zero rather than an out-of-band marker because zero is the one value the model
    /// can be asked for in plain language without naming a programming construct — and
    /// because a real set count, rep count or load of zero is meaningless anyway, so
    /// nothing legitimate is shadowed by it.
    static let unstatedNumber = 0

    /// Applied in Swift when the description stated no set count — never asked of the
    /// model. A prompt that says "suggest three or four" is answered by a ~3B model
    /// completing the shape its instructions describe, which is exactly how this app
    /// once had figures fabricated at it.
    static let defaultSetCount = 3

    /// Applied in Swift when the description stated no rep count, for the same reason.
    static let defaultReps = 10

    /// The rest between sets when the description stated none — the `ExerciseSet`
    /// model's own default, applied here in Swift and never written into the prompt.
    static let defaultRestTime: TimeInterval = 60

    /// Bounds on what a drafted exercise may carry into the store. A person typing a
    /// sentence is not typing inside a stepper, and the model copies what they wrote.
    static let maximumSetCount = 20
    static let maximumReps = 100
    /// The same ceilings `ConfigureExerciseSetsView`'s rep-goal and rest steppers use, so a
    /// drafted value always opens in the editor as something the editor could have set.
    static let maximumRepGoal = 99
    static let maximumRestTime: TimeInterval = 600

    // MARK: - Dependencies

    /// The existing folded, diacritic- and case-insensitive, cross-language matcher.
    /// **There is no second matcher in this app** — this one already returns
    /// `.resolved` / `.ambiguous` / `.noMatch` against the live library.
    private let resolver = ExerciseNameResolver()

    /// What each drafted name resolved to, remembered for the life of this instance.
    ///
    /// **This is why the type is a class and not a struct.** `ground(_:…)` runs on every
    /// streamed snapshot over the *whole* cumulative draft, and a single
    /// `ExerciseNameResolver.resolve` walks the library up to three times (exact,
    /// substring, token overlap), folding every library name on each pass — four
    /// allocations per name per pass. Without this memo the main-actor cost of one
    /// drafting session is O(snapshots × drafted entries × library × 3), which is
    /// hundreds of thousands of short-string allocations while the sheet animates.
    /// With it, each distinct drafted name is resolved exactly once.
    ///
    /// **One instance per library snapshot.** The memo is keyed by name alone, so an
    /// instance must not outlive the `[Exercise]` it was used with — build a fresh
    /// grounder whenever the library is re-fetched. `RoutineDraftViewModel` does.
    private var matches: [String: GroundedDraftExercise.Match] = [:]

    /// One identity per drafted position, handed out once and reused on every later
    /// snapshot.
    ///
    /// Each streamed snapshot is cumulative, so the entry at a given index is the same
    /// entry throughout the session. Minting a fresh `UUID` per snapshot would give the
    /// review list a brand-new identity for every row on every token burst — SwiftUI
    /// would rebuild the whole list rather than diff it (CLAUDE.md rendering rule 8), and
    /// a picker opened on a row would be pointing at an id that no longer exists.
    private var entryIDs: [UUID] = []

    init() {}

    // MARK: - Grounding

    /// Grounds one streaming snapshot against `library`.
    ///
    /// Safe to call on every snapshot: it allocates no formatter, touches no store, and
    /// resolves each distinct drafted name against the library exactly once for the life
    /// of this instance (see `matches` — a cache miss is what costs three library walks,
    /// and a streaming draft repeats the same names on every snapshot).
    ///
    /// - Parameter weightUnit: the unit `snapshot`'s weights are written in. Converted to
    ///   canonical kilograms here, exactly once — the app never stores a converted value
    ///   that has been converted twice.
    /// - Parameter personWords: everything the person typed in this drafting
    ///   conversation. When given, **a drafted name must come from it** — see
    ///   `isInPersonWords` — and **so must its rest time, rep range and load**, checked by
    ///   `RoutineDraftFigures`. `nil` skips both checks; only tests of the other passes
    ///   use it.
    func ground(
        _ snapshot: RoutineDraftSnapshot,
        library: [Exercise],
        weightUnit: WeightUnit,
        personWords: String? = nil
    ) -> GroundedRoutineDraft {
        var exercises: [GroundedDraftExercise] = []
        var dropped: [String] = []
        let source = personWords.map { Set(words(of: resolver.fold($0))) }
        let routineName = snapshot.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let figures = personWords.map(RoutineDraftFigures.init(words:))
        let segments = personWords.map {
            // A figure word the loop below skips ("Pause") is no exercise to segment by.
            RoutineDraftFigures.segments(
                for: snapshot.exercises.map { RoutineDraftFigures.isFigureVocabulary($0.name) ? "" : $0.name },
                in: $0
            )
        }

        for (index, entry) in snapshot.exercises.enumerated() {
            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            // The model was told to copy names from the person's words. A name that is
            // not in them was invented — measured on device: "eine push routine" came
            // back as twelve made-up rows (Push, Pull, Squat, Legs, Chest, …), one of which
            // ("Pull") the library confidently resolved to Face Pulls.
            if let source, !isInPersonWords(name, source: source) {
                if !dropped.contains(name) { dropped.append(name) }
                continue
            }

            // "Pause", "Sätze", "kg": a figure's word written out as an exercise. Not
            // reported as dropped — it was never meant as one.
            if RoutineDraftFigures.isFigureVocabulary(name) { continue }

            let libraryMatch = match(for: name, in: library)
            // "Push" in "a push routine" *is* in the person's words — as the kind of
            // workout, which the model also wrote as the routine's name. A name the library
            // cannot place that merely repeats the routine name is not an exercise. Not
            // reported as dropped: it was never meant as one.
            if case .unmatched = libraryMatch, isPartOfRoutineName(name, routineName) { continue }

            // A stretch holding more than one set group also holds an exercise the model
            // left out — its figures are not this exercise's to recover.
            let segment = segments?[index]
                .map(RoutineDraftFigures.init(words:))
                .flatMap { $0.setGroupCount <= 1 ? $0 : nil }
            let goal = repRangeGoal(span: entry.repRange, figures: figures, segment: segment)
            exercises.append(
                GroundedDraftExercise(
                    id: identity(at: index),
                    draftedName: name,
                    match: libraryMatch,
                    setCount: boundedSetCount(entry.setCount),
                    isSetCountStated: entry.setCount > Self.unstatedNumber,
                    reps: reps(entry.reps, within: goal),
                    weightKilograms: kilograms(load(of: entry, figures: figures, segment: segment), in: weightUnit),
                    targetRepMin: goal?.min,
                    targetRepMax: goal?.max,
                    restTime: restTime(entry.restUnit, amount: entry.restAmount, figures: figures)
                )
            )
        }

        return GroundedRoutineDraft(name: routineName, exercises: exercises, droppedNames: dropped)
    }

    // MARK: - Provenance

    /// Whether every word of a drafted name is a word the person used.
    ///
    /// **Whole words, not substrings.** A substring test let "Rücken" through because
    /// `fold("Bankdrücken")` contains `"ruecken"` — measured on device, 2026-09-24, as the
    /// one invented row that survived. A drafted word matches a word the person typed when
    /// the two are equal or differ only by a short ending ("Squat"/"squats",
    /// "Kniebeuge"/"Kniebeugen"): a false *drop* loses something the person said, so
    /// inflection is forgiven, but a word hidden inside a longer one is not theirs. This is
    /// a provenance check, not a matcher: the library is never consulted here.
    private func isInPersonWords(_ name: String, source: Set<String>) -> Bool {
        let drafted = words(of: resolver.fold(name))
        guard !drafted.isEmpty else { return false }
        return drafted.allSatisfy { word in
            source.contains(word) || source.contains { Self.differsOnlyByEnding(word, $0) }
        }
    }

    /// The longest ending that still counts as the same word — a plural or a German
    /// inflection, never a second word compounded on.
    private static let maximumEndingLength = 2

    private static func differsOnlyByEnding(_ lhs: String, _ rhs: String) -> Bool {
        let (short, long) = lhs.count <= rhs.count ? (lhs, rhs) : (rhs, lhs)
        return short.count >= 3
            && long.hasPrefix(short)
            && long.count - short.count <= maximumEndingLength
    }

    private func isPartOfRoutineName(_ name: String, _ routineName: String) -> Bool {
        guard !routineName.isEmpty else { return false }
        let routineWords = Set(words(of: resolver.fold(routineName)))
        let nameWords = words(of: resolver.fold(name))
        return !nameWords.isEmpty && nameWords.allSatisfy(routineWords.contains)
    }

    private func words(of folded: String) -> [String] {
        folded.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// How the library answers `name`. Memoized — see `matches`.
    ///
    /// `.resolved` aggregates library rows that share one folded *name*, so they are
    /// indistinguishable by the only thing the model gave us; taking the first is not a
    /// coin toss between different exercises. `.ambiguous` keeps its candidates, because
    /// a short correct list is exactly what makes that case answerable in one tap.
    private func match(for name: String, in library: [Exercise]) -> GroundedDraftExercise.Match {
        let key = name.lowercased()
        if let cached = matches[key] { return cached }

        let match: GroundedDraftExercise.Match
        switch resolver.resolve(name, in: library) {
        case .resolved(let resolved):
            match = resolved.first.map { .resolved($0) } ?? .unmatched
        case .ambiguous(let names):
            // Back to library rows, in the order the resolver named them, and keeping
            // same-name duplicates: the person picks one of *their* exercises, so the
            // list has to be exercises rather than the strings the resolver reports.
            let byName = Dictionary(grouping: library) { $0.name.lowercased() }
            let candidates = names.flatMap { byName[$0.lowercased()] ?? [] }
            // An ambiguous answer whose names no longer name anything in this library is
            // not something to offer an empty list for.
            match = candidates.isEmpty ? .unmatched : .ambiguous(candidates)
        case .noMatch:
            match = .unmatched
        }
        matches[key] = match
        return match
    }

    /// The identity of the drafted exercise at `index`, stable for the life of this
    /// instance — see `entryIDs`.
    private func identity(at index: Int) -> UUID {
        while entryIDs.count <= index { entryIDs.append(UUID()) }
        return entryIDs[index]
    }
}
