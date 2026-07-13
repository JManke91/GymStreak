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
    /// have been applied because the goal was hit, and applying it resets the
    /// actual reps to the range minimum, which would otherwise disqualify.
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
