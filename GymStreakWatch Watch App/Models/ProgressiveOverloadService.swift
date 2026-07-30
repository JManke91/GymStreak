//
//  ProgressiveOverloadService.swift
//  GymStreakWatch Watch App
//
//  Watch copy of `GymStreak/Domain/Services/ProgressiveOverloadService.swift`
//  (progressive-overload ticket 04).
//
//  WHY A COPY: the watch target must not import iOS `Domain/` — that layer owns
//  SwiftData `@Model` types and the watch deliberately has no SwiftData (see
//  docs/architecture.md). The repository's established convention for logic
//  both targets need is a per-target copy, exactly as done for
//  `WatchSyncStateStore`, `WatchRoutineTemplateFold`, and
//  `WatchWorkoutStructuralReducer`. Keeping the qualify/apply rules identical is
//  what guarantees a suggestion shown on the Watch and one shown on iPhone
//  agree, and that the values the Watch proposes are the values iOS would have
//  computed itself.
//
//  Everything below `MARK: - Shared logic` is character-identical to the iOS
//  original; only the small `ExerciseLoadBehavior` copy above it is added,
//  because the watch models carry load behavior as a raw string. Unit coverage
//  lives against the iOS original (`GymStreakTests/ProgressiveOverloadServiceTests`)
//  — there is no watch unit-test target.
//

import Foundation

/// Watch copy of the iOS `ExerciseLoadBehavior` domain enum. The watch wire
/// models carry `loadBehaviorRaw` strings; `from(raw:)` is the one place that
/// converts, so an unknown/absent raw value degrades to `.resistance` rather
/// than silently reversing the direction of a weight change.
enum ExerciseLoadBehavior: String, Codable, CaseIterable, Hashable {
    case resistance
    case counterweightAssistance

    var isCounterweightAssistance: Bool {
        self == .counterweightAssistance
    }

    static func from(raw: String?) -> ExerciseLoadBehavior {
        guard let raw, let behavior = ExerciseLoadBehavior(rawValue: raw) else { return .resistance }
        return behavior
    }
}

// MARK: - Shared logic

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
