import Foundation

/// Single source of truth for rep-range progressive-overload decisions:
/// when an exercise qualifies for a weight-increase suggestion and what
/// applying the increase does to its sets.
///
/// Pure value math over plain types — no SwiftData/SwiftUI — so every surface
/// (routine editor, active workout, completion screen, history, watch) applies
/// identical rules. The watch target can reuse a copy of this file.
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

/// The weight steps overload surfaces offer, shared by BOTH platforms so they
/// cannot drift apart again.
///
/// `options` are the PRESETS: 0.5 is the micro-loading step (fractional plates,
/// and the smallest meaningful move on many machine stacks); 1.25 / 2.5 / 5 are
/// the standard plate steps. The iOS `WeightIncreaseSheet` shows exactly these
/// as a radio list, and 2.5 is the one-tap default on both platforms.
///
/// `minimum`/`maximum`/`step` additionally describe FREE selection, which the
/// watch's Digital Crown picker uses so a user who wants an unusual jump is not
/// boxed into the presets. The stride is 0.25 so every preset — 1.25 included —
/// lands exactly on the grid. The upper bound is deliberately generous rather
/// than realistic: a single-session jump that large is absurd, but a finite
/// bound is required (the unbounded `digitalCrownRotation` overload carries no
/// stride and no haptic detents, so it is the wrong tool for a stepped value).
///
/// Display all of these with two fraction digits — `%.2g` and the default
/// `Measurement` precision both round 1.25 to a misleading "1.2".
enum ProgressiveOverloadIncrement {
    static let options: [Double] = [0.5, 1.25, 2.5, 5.0]
    static let `default`: Double = 2.5

    static let minimum: Double = 0.25
    static let maximum: Double = 50.0
    static let step: Double = 0.25

    /// Clamps to the selectable range and snaps to the nearest stride, so a
    /// value from any source stays on the same grid the crown moves along.
    static func normalized(_ value: Double) -> Double {
        let clamped = min(max(value, minimum), maximum)
        return (clamped / step).rounded() * step
    }
}
