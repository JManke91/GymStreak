//
//  RoutineDraftEntry.swift
//  GymStreak
//
//  One drafted exercise exactly as the model wrote it — before it has met the library or
//  the person's words. See docs/ai-coach-routine-drafting.md §4 and §4a.
//
//  Plain Foundation, like the rest of `RoutineDraftModels.swift`: `Data/` maps the
//  `@Generable` schema into this, so nothing past it sees a framework type.
//

import Foundation

/// One exercise as the model wrote it: a free-text name plus raw numbers.
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
    /// The rep-range goal as the words the model copied ("8 bis 12"), or empty. Only a
    /// span the grounder can parse *and* find in the person's words becomes a goal;
    /// anything else is "no goal".
    let repRange: String
    /// Rest between sets as the model copied it: the unit word it saw and the number
    /// beside it, converted and checked against the person's words by the grounder.
    let restUnit: RestUnit
    let restAmount: Double

    init(
        name: String,
        setCount: Int,
        reps: Int,
        weight: Double,
        repRange: String = "",
        restUnit: RestUnit = .unstated,
        restAmount: Double = 0
    ) {
        self.name = name
        self.setCount = setCount
        self.reps = reps
        self.weight = weight
        self.repRange = repRange
        self.restUnit = restUnit
        self.restAmount = restAmount
    }

    /// The unit of a drafted rest time. The plain-Foundation twin of the schema's
    /// `RoutineDraftRestUnit`, so nothing past `Data/` sees a `@Generable` type.
    enum RestUnit: Equatable, Sendable {
        case unstated
        case seconds
        case minutes
    }
}
