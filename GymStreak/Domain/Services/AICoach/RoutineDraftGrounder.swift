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
///    an exercise that does not resolve is excluded and reported, never created, never
///    guessed at. This app does not invent library entries on the model's word.
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

    /// The rest between sets on every drafted set. The description has no way to say it
    /// yet — ticket 05 gives it one.
    static let defaultRestTime: TimeInterval = 60

    /// Bounds on what a drafted exercise may carry into the store. A person typing a
    /// sentence is not typing inside a stepper, and the model copies what they wrote.
    static let maximumSetCount = 20
    static let maximumReps = 100

    // MARK: - Dependencies

    /// The existing folded, diacritic- and case-insensitive, cross-language matcher.
    /// **There is no second matcher in this app** — this one already returns
    /// `.resolved` / `.ambiguous` / `.noMatch` against the live library.
    private let resolver = ExerciseNameResolver()

    /// What each drafted name resolved to, remembered for the life of this instance.
    /// `nil` inside the optional is a real answer — "the library could not place this" —
    /// which is why the value is a double optional rather than a sentinel.
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
    private var resolutions: [String: Exercise?] = [:]

    init() {}

    // MARK: - Grounding

    /// Grounds one streaming snapshot against `library`.
    ///
    /// Safe to call on every snapshot: it allocates no formatter, touches no store, and
    /// resolves each distinct drafted name against the library exactly once for the life
    /// of this instance (see `resolutions` — a cache miss is what costs three library
    /// walks, and a streaming draft repeats the same names on every snapshot).
    ///
    /// - Parameter weightUnit: the unit `snapshot`'s weights are written in. Converted to
    ///   canonical kilograms here, exactly once — the app never stores a converted value
    ///   that has been converted twice.
    func ground(
        _ snapshot: RoutineDraftSnapshot,
        library: [Exercise],
        weightUnit: WeightUnit
    ) -> GroundedRoutineDraft {
        var exercises: [GroundedDraftExercise] = []
        var unmatched: [String] = []
        var seenUnmatched = Set<String>()

        for entry in snapshot.exercises {
            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            if let exercise = resolution(for: name, in: library) {
                exercises.append(
                    GroundedDraftExercise(
                        exercise: exercise,
                        setCount: boundedSetCount(entry.setCount),
                        reps: boundedReps(entry.reps),
                        weightKilograms: kilograms(entry.weight, in: weightUnit)
                    )
                )
                continue
            }

            // Ambiguous and unmatched are the same outcome *for this ticket*: there is
            // no library exercise this draft may safely claim, so it is named as left
            // out rather than resolved on the app's guess. Ticket 02 splits them apart
            // and makes both answerable by the person.
            if seenUnmatched.insert(name.lowercased()).inserted {
                unmatched.append(name)
            }
        }

        return GroundedRoutineDraft(
            name: snapshot.name.trimmingCharacters(in: .whitespacesAndNewlines),
            exercises: exercises,
            unmatchedNames: unmatched
        )
    }

    /// The library exercise `name` resolves to, or `nil` when the library cannot place
    /// it. Memoized — see `resolutions`.
    ///
    /// `.resolved` aggregates library rows that share one folded *name*, so they are
    /// indistinguishable by the only thing the model gave us; taking the first is not a
    /// coin toss between different exercises. `.ambiguous` and `.noMatch` both answer
    /// `nil`: neither names an exercise this draft may claim.
    private func resolution(for name: String, in library: [Exercise]) -> Exercise? {
        let key = name.lowercased()
        if let cached = resolutions[key] { return cached }

        let resolved: Exercise?
        switch resolver.resolve(name, in: library) {
        case .resolved(let matches): resolved = matches.first
        case .ambiguous, .noMatch: resolved = nil
        }
        resolutions[key] = resolved
        return resolved
    }

    // MARK: - Bounds

    /// The stated set count, the Swift default when none was stated, bounded either way.
    func boundedSetCount(_ stated: Int) -> Int {
        guard stated > Self.unstatedNumber else { return Self.defaultSetCount }
        return min(stated, Self.maximumSetCount)
    }

    /// The stated rep count, the Swift default when none was stated, bounded either way.
    func boundedReps(_ stated: Int) -> Int {
        guard stated > Self.unstatedNumber else { return Self.defaultReps }
        return min(stated, Self.maximumReps)
    }

    /// A stated display-unit load as canonical kilograms, clamped to the same ceiling
    /// every typed weight in the app is clamped to. An unstated or negative load is a
    /// drafted exercise without a load, which is what a bodyweight movement needs.
    func kilograms(_ stated: Double, in unit: WeightUnit) -> Double {
        guard stated > 0 else { return 0 }
        return unit.clampedKilograms(fromDisplay: stated)
    }
}
