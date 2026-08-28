import Foundation

/// Single source of truth for rep-range progressive-overload decisions:
/// when an exercise qualifies for a weight-increase suggestion and what
/// applying the increase does to its sets.
///
/// Pure value math over plain types — no SwiftData/SwiftUI — so every surface
/// (routine editor, active workout, completion screen, history, watch) applies
/// identical rules. The watch keeps its own copy of this file
/// (`GymStreakWatch Watch App/Models/ProgressiveOverloadService.swift`),
/// including the per-unit `ProgressiveOverloadIncrement` grids below — these are
/// per-target duplicated copies, not shared code, so keeping the two identical
/// is manual and a drift means the watch proposes a different increase than the
/// phone for the same set.
///
/// Every `increment` and `weight` here is in **canonical kilograms**. Only
/// `ProgressiveOverloadIncrement` speaks display units, and the conversion
/// happens once at the surface that applies the increase.
enum ProgressiveOverloadService {

    /// A set's progress toward the rep-range goal, decoupled from model types.
    struct SetProgress {
        let reps: Int
        let isCompleted: Bool
    }

    /// The state of an exercise's sets after a weight increase: one new weight
    /// per input weight (same order) and the reps every set resets to.
    struct AppliedIncrease {
        let weights: [Double]
        let reps: Int
    }

    // MARK: - Qualify

    /// Routine template: every set's planned reps has reached the upper limit.
    /// Template sets have no meaningful completion state, so only reps count.
    static func templateQualifiesForIncrease(reps: [Int], targetRepMax: Int?) -> Bool {
        qualifies(sets: reps.map { SetProgress(reps: $0, isCompleted: true) }, targetRepMax: targetRepMax)
    }

    /// Workout: all sets completed AND actual reps ≥ target rep max.
    /// `overloadAlreadyApplied` short-circuits to true — the overload could only
    /// have been applied because the goal was hit. It is belt-and-braces since
    /// applying stopped rewriting the performed reps (the sets still read at or
    /// above the rep max on their own), and it keeps the already-applied state
    /// stable for any surface that recomputes qualification.
    static func workoutQualifiesForIncrease(
        sets: [SetProgress],
        targetRepMax: Int?,
        overloadAlreadyApplied: Bool = false
    ) -> Bool {
        if overloadAlreadyApplied { return true }
        return qualifies(sets: sets, targetRepMax: targetRepMax)
    }

    private static func qualifies(sets: [SetProgress], targetRepMax: Int?) -> Bool {
        guard let repMax = targetRepMax, !sets.isEmpty else { return false }
        return sets.allSatisfy { $0.isCompleted && $0.reps >= repMax }
    }

    // MARK: - Apply

    /// Direction-aware weight step: a counterweight stack helps the user, so
    /// progression means removing assistance (clamped at 0).
    static func increasedWeight(
        _ weight: Double,
        increment: Double,
        loadBehavior: ExerciseLoadBehavior
    ) -> Double {
        loadBehavior.isCounterweightAssistance ? max(0, weight - increment) : weight + increment
    }

    static func applyIncrease(
        toWeights weights: [Double],
        increment: Double,
        targetRepMin: Int,
        loadBehavior: ExerciseLoadBehavior
    ) -> AppliedIncrease {
        AppliedIncrease(
            weights: weights.map { increasedWeight($0, increment: increment, loadBehavior: loadBehavior) },
            reps: targetRepMin
        )
    }
}

/// The weight steps overload surfaces offer, expressed in the unit the user
/// reads and types — one grid per unit.
///
/// **The pound grid is a parallel set of real plate steps, not converted
/// kilograms.** Converting the kilogram list gives 1.1 / 2.76 / 5.51 / 11.02 lb,
/// which is nonsense on a plate rack: nobody owns a 2.76 lb plate. A pounds user
/// gets 1.25 / 2.5 / 5 / 10 lb, the steps their gym actually stocks. Whatever
/// they pick is converted to kilograms exactly once, where it is applied to a
/// weight — the grids themselves never leave display space.
///
/// `options` are the PRESETS. In kilograms 0.5 is the micro-loading step
/// (fractional plates, and the smallest meaningful move on many machine stacks)
/// and 1.25 / 2.5 / 5 are the standard plate steps; in pounds 1.25 is the
/// micro-plate. The iOS `WeightIncreaseSheet` shows exactly these as a radio
/// list, and `defaultOption` is the one-tap default.
///
/// `minimum`/`maximum`/`step` additionally describe FREE selection, which the
/// watch's Digital Crown picker uses so a user who wants an unusual jump is not
/// boxed into the presets. The stride is 0.25 in both units so every preset —
/// 1.25 included — lands exactly on the grid. The upper bound is deliberately
/// generous rather than realistic: a single-session jump that large is absurd,
/// but a finite bound is required (the unbounded `digitalCrownRotation` overload
/// carries no stride and no haptic detents, so it is the wrong tool for a
/// stepped value).
///
/// Display all of these through `WeightFormatting`, whose `.fractionLength(0...2)`
/// renders 1.25 as "1.25" — `%.2g` and the default `Measurement` precision both
/// round it to a misleading "1.2".
enum ProgressiveOverloadIncrement {

    /// One unit's grid. Every value is in that unit's own display space.
    struct Grid {
        let options: [Double]
        let defaultOption: Double
        let minimum: Double
        let maximum: Double
        let step: Double
    }

    /// The two grids, side by side so a change to one is read against the other.
    static func grid(for unit: WeightUnit) -> Grid {
        switch unit {
        case .kilograms:
            Grid(options: [0.5, 1.25, 2.5, 5], defaultOption: 2.5, minimum: 0.25, maximum: 50, step: 0.25)
        case .pounds:
            Grid(options: [1.25, 2.5, 5, 10], defaultOption: 5, minimum: 0.25, maximum: 100, step: 0.25)
        }
    }

    /// Clamps a display-space value to `unit`'s selectable range and snaps it to
    /// that unit's stride, so a value from any source stays on the same grid the
    /// crown moves along.
    static func normalized(_ value: Double, in unit: WeightUnit) -> Double {
        let grid = grid(for: unit)
        let clamped = min(max(value, grid.minimum), grid.maximum)
        return (clamped / grid.step).rounded() * grid.step
    }
}
