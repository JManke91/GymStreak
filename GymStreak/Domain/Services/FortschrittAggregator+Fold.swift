//
//  FortschrittAggregator+Fold.swift
//  GymStreak
//
//  The Fortschritt row's accumulators and its set-level reduction, split out of
//  FortschrittAggregator.swift (2026-08-24) when per-usage aggregation pushed that file
//  past this project's size convention. No API change: these are the same nested types
//  and the same reduction, addressed the same way.
//
//  They are `internal` rather than `private` only because they now live in a second file
//  of the same type — nothing outside `FortschrittAggregator` builds or reads them.
//

import Foundation
import SwiftData

extension FortschrittAggregator {

    /// One history row reduced to the single number its usage's series carries for that
    /// workout: the **heaviest effective weight** across its completed sets, or the least
    /// assistance when a counterweight row has no body-mass snapshot to turn into an
    /// effective load.
    ///
    /// This is deliberately the same reduction `ExerciseProgressAggregator.buildProgress`
    /// applies to `ExerciseProgressDataPoint.maxWeight`, so a row's sparkline is the chart's
    /// own series for the same usage. It used to fold to the best estimated
    /// 1RM — which is a **Pro-gated metric** (`ProFeatureCaps.freeChartMetric` is
    /// `.maxWeight`), so the list handed every free user a number they could not read on
    /// the screen it opens. See `docs/progress-charts.md`.
    ///
    /// A counterweight row is folded in **both** value spaces at once, because which one
    /// its series ends up in is a property of the whole series and is not knowable here:
    /// one snapshot-less session drops every point of that series to raw assistance
    /// (`FortschrittAggregator.build`). Deciding here instead is what used to put an
    /// estimated physical load and a machine's assistance number into one sparkline.
    /// Folding both now costs one `min` per set and keeps the decision to a single
    /// traversal of the session graph.
    ///
    /// A row whose sets carry nothing comparable still yields a value of 0. The workout is
    /// counted regardless — `FortschrittAggregator.build` counts it off `didRecordAnything`,
    /// which only asks whether the row had a completed set at all.
    static func foldSets(
        of workoutExercise: WorkoutExercise,
        in session: WorkoutSession
    ) -> SessionFold {
        let behavior = workoutExercise.loadBehavior
        let canUseEffectiveLoad = !behavior.isCounterweightAssistance || session.bodyWeightKg != nil
        var fold = SessionFold(canUseEffectiveLoad: canUseEffectiveLoad)

        let usePlanned = workoutExercise.progressiveOverloadApplied
        for set in workoutExercise.setsList where set.isCompleted {
            let weight = usePlanned ? set.plannedWeight : set.actualWeight
            // Reps do not enter a max-weight series. The old `reps > 0` guard came from the
            // 1RM fold and had no counterpart in `buildProgress`, which gates on weight
            // alone — one fewer way for the two surfaces to differ.
            guard weight > 0 || behavior.isCounterweightAssistance else { continue }
            if canUseEffectiveLoad,
               let effective = ExerciseLoadMetrics.effectiveWeight(
                enteredWeight: weight,
                behavior: behavior,
                bodyWeightKg: session.bodyWeightKg
               ) {
                // Heavier is the better set. `effectiveValue` starts at 0 and an effective
                // weight is never negative, so plain max also covers the first recorded set.
                fold.effectiveValue = max(fold.effectiveValue, effective)
            }
            if behavior.isCounterweightAssistance {
                // Raw assistance: *least* assistance is the better set, so fold with min.
                fold.recordAssistance(
                    fold.hasAssistanceValue ? min(fold.assistanceValue, weight) : weight
                )
            }
        }
        return fold
    }

    /// Everything one library exercise's row is built from.
    struct Accumulator {
        var displayName: String
        var muscleGroups: [String]
        var loadBehavior: ExerciseLoadBehavior
        /// Distinct completed sessions containing the exercise, in any usage.
        var sessionCount = 0
        var lastPerformed: Date?
        var usages: [ExerciseUsage.Key: UsageAccumulator] = [:]
    }

    /// One usage's series, plus what the label is taken from.
    struct UsageAccumulator {
        /// Taken from the usage's most recent row (`descriptorRank`), because the rep
        /// range and routine name are denormalized per workout.
        var descriptor: ExerciseUsage
        var descriptorRank: ExerciseUsageResolver.DescriptorRank
        var lastPerformed: Date
        var lastPerformedOrder: Int
        var sessionValues: [(date: Date, fold: SessionFold)] = []
    }

    /// A single session's folded value for one usage, carried in both value spaces so
    /// the series can pick one afterwards.
    struct SessionFold {
        /// Heaviest effective weight across the completed sets. Only filled when the
        /// session can be read as physical load at all. Needs no "was it set" flag: the
        /// max-fold seeded at 0 is correct, because an effective weight is never negative.
        var effectiveValue: Double = 0
        /// Least raw assistance entered — filled for every counterweight row, snapshot
        /// or not, because a snapshot-less session elsewhere in the series can still
        /// force this space on it.
        var assistanceValue: Double = 0
        /// Whether `assistanceValue` holds a set's number yet. The min-fold needs this to
        /// tell "nothing recorded" from a legitimately recorded 0 (an assisted set
        /// performed with no counterweight at all), which is a best value it must keep.
        var hasAssistanceValue = false
        /// Whether this session carried what it takes to express its work as physical
        /// load: a body-mass snapshot, or a behaviour that never needed one.
        let canUseEffectiveLoad: Bool

        /// The number this session contributes once the *series* has picked its space.
        func value(usingEffectiveLoad: Bool) -> Double {
            usingEffectiveLoad ? effectiveValue : assistanceValue
        }

        mutating func recordAssistance(_ newValue: Double) {
            assistanceValue = newValue
            hasAssistanceValue = true
        }
    }
}
