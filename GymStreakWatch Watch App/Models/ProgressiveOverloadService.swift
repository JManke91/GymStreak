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
//  because the watch models carry load behavior as a raw string.
//
//  COVERAGE: this copy is asserted on directly by
//  `GymStreakWatchTests/ProgressiveOverloadServiceTests`, whose assertions are
//  kept identical to the iOS twin (`GymStreakTests/ProgressiveOverloadServiceTests`)
//  so a behavioural drift between the two copies fails the watch suite. See
//  docs/watch-unit-tests.md.
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

    // MARK: - Uniformity

    /// Weight equality for values that made a JSON round trip or were
    /// recomputed by a different surface. The tolerance is orders of magnitude
    /// below the smallest offered step (1.25), so it can never mask a genuine
    /// third value — it only avoids a spurious mismatch from a last-bit
    /// representation difference.
    static func weightsMatch(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 0.0001
    }

    /// Whether every set ends up at the SAME weight — false for a pyramid or
    /// drop scheme, where no single number is true of all of them.
    ///
    /// ONE definition, because every surface must reach the same verdict on the
    /// same scheme: the Watch recap decides whether to name a weight, the iOS
    /// ingest decides it again from the delivered payload, and History decides
    /// it a third time from the live template. `weightsMatch` is a tolerance
    /// comparison and therefore NOT transitive — anchoring every comparison on
    /// the first weight is what makes those verdicts agree, so callers must not
    /// roll their own pairwise loop.
    ///
    /// An empty scheme is vacuously uniform; callers that need "there is a
    /// weight to name" must check for a first element themselves.
    static func haveUniformWeights(_ weights: [Double]) -> Bool {
        guard let first = weights.first else { return true }
        return weights.allSatisfy { weightsMatch($0, first) }
    }
}

/// The weight steps overload surfaces offer, expressed in the unit the user
/// reads — one grid per unit.
///
/// **VERBATIM COPY of the iOS `ProgressiveOverloadIncrement`**
/// (`GymStreak/Domain/Services/ProgressiveOverloadService.swift`). These are
/// per-target duplicated copies, not shared code, so keeping the two grids
/// identical is manual: a drift here means the watch proposes a different
/// increase than the phone for the same set. `GymStreakWatchTests` asserts the
/// watch copy with the same assertions as the iOS twin for exactly that reason.
///
/// **The pound grid is a parallel set of real plate steps, not converted
/// kilograms.** Converting the kilogram list gives 1.1 / 2.76 / 5.51 / 11.02 lb,
/// which is nonsense on a plate rack: nobody owns a 2.76 lb plate. A pounds user
/// gets 1.25 / 2.5 / 5 / 10 lb, the steps their gym actually stocks. Whatever
/// they pick is converted to kilograms exactly once, in the picker that applies
/// it — the grids themselves never leave display space.
///
/// `options` are the PRESETS. In kilograms 0.5 is the micro-loading step
/// (fractional plates, and the smallest meaningful move on many machine stacks)
/// and 1.25 / 2.5 / 5 are the standard plate steps; in pounds 1.25 is the
/// micro-plate. `defaultOption` is the one-tap default.
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
/// Display all of these through `WatchWeightFormatting.incrementLabel`, whose
/// `.fractionLength(0...2)` renders 1.25 as "1.25" — `%.2g` and the default
/// `Measurement` precision both round it to a misleading "1.2".
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
