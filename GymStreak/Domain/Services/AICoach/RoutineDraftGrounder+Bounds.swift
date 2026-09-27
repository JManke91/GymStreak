//
//  RoutineDraftGrounder+Bounds.swift
//  GymStreak
//
//  Every figure a drafted exercise may carry into the store — set and rep counts, the
//  rep-range goal, the rest time and the load — bounded, defaulted in Swift, and checked
//  against what the person typed. See docs/ai-coach-routine-drafting.md §4a and §6.
//

import Foundation

extension RoutineDraftGrounder {

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

    /// The rep-range goal in a copied span ("8 bis 12", "8-12"), or `nil` — the ordinary
    /// answer, and the answer for an empty or unparsable span.
    ///
    /// - Parameter segment: this exercise's own stretch of the person's words, when the
    ///   segmentation could be trusted (`RoutineDraftFigures.segments`). Consulted only
    ///   when the model's span is not a typed range: a model that copied no span, or a
    ///   wrong one, still gets the one range typed there. Never used to overrule a span
    ///   the words confirm.
    func repRangeGoal(
        span: String,
        figures: RoutineDraftFigures? = nil,
        segment: RoutineDraftFigures? = nil
    ) -> (min: Int, max: Int)? {
        if let range = RoutineDraftFigures(words: span).firstRange,
           let goal = repRangeGoal(low: range.low, high: range.high, figures: figures) {
            return goal
        }
        guard let typed = segment?.onlyRange else { return nil }
        return repRangeGoal(low: typed.low, high: typed.high)
    }

    /// The load to draft, in the reader's display unit: the model's when the person typed
    /// it as a load, else the one load typed with a unit in this exercise's own stretch of
    /// words (only when that stretch can be trusted), else none. Never a figure the person
    /// did not type as a load, and never a correct model value overruled by a segment.
    func load(
        of entry: RoutineDraftEntry,
        figures: RoutineDraftFigures?,
        segment: RoutineDraftFigures?
    ) -> Double {
        guard let figures else { return entry.weight }
        if entry.weight > 0,
           figures.isStatedLoad(entry.weight, setCount: entry.setCount, reps: entry.reps) {
            return entry.weight
        }
        return segment?.onlyUnitLoad ?? 0
    }

    /// The rep-range goal the description stated, or `nil` — which is the ordinary answer.
    ///
    /// **Absence is never filled in.** Both ends must be stated and the low end must be
    /// below the high one: "3 sets of 8" copied into both fields is a rep count, not a
    /// range, and one stated end alone is not a goal the person set. With `figures`, the
    /// pair must also be one the person typed — the model has been measured drafting
    /// "3x8-12 60kg" as 6–12.
    func repRangeGoal(low: Int, high: Int, figures: RoutineDraftFigures? = nil) -> (min: Int, max: Int)? {
        guard low > Self.unstatedNumber, high > low else { return nil }
        if let figures, !figures.isStatedRange(low: low, high: high) { return nil }
        let upper = min(high, Self.maximumRepGoal)
        guard low < upper else { return nil }
        return (low, upper)
    }

    /// The reps each set starts at. With a goal, a stated count is kept inside it and an
    /// unstated one starts at the goal's low end — the same convention the seeded routines
    /// use, and where progressive overload expects a set to begin.
    func reps(_ stated: Int, within goal: (min: Int, max: Int)?) -> Int {
        guard let goal else { return boundedReps(stated) }
        guard stated > Self.unstatedNumber else { return goal.min }
        return min(max(stated, goal.min), goal.max)
    }

    /// The rest between sets in seconds — the stated one, or the Swift default.
    ///
    /// The model copies the number and names the unit; Swift converts, so the model never
    /// does arithmetic. Its unit is then only a hint: a rest over ten "minutes" is seconds
    /// read wrong (the rest editor stops at ten minutes), and five "seconds" or fewer is
    /// minutes. With `figures` the result must also be a rest the person typed.
    func restTime(
        _ unit: RoutineDraftEntry.RestUnit,
        amount: Double,
        figures: RoutineDraftFigures? = nil
    ) -> TimeInterval {
        let drafted: TimeInterval? = switch unit {
        case _ where amount <= 0: nil
        case .unstated: nil
        case .minutes: amount > Self.maximumRestTime / 60 ? amount : amount * 60
        case .seconds: amount <= 5 ? amount * 60 : amount
        }
        let stated = figures.map { $0.statedRest(drafted: drafted, draftedAmount: amount) } ?? drafted
        guard let stated, stated > 0 else { return Self.defaultRestTime }
        return min(stated.rounded(), Self.maximumRestTime)
    }

    /// A stated display-unit load as canonical kilograms, clamped to the same ceiling
    /// every typed weight in the app is clamped to. An unstated or negative load is a
    /// drafted exercise without a load, which is what a bodyweight movement needs.
    func kilograms(_ stated: Double, in unit: WeightUnit) -> Double {
        guard stated > 0 else { return 0 }
        return unit.clampedKilograms(fromDisplay: stated)
    }
}
