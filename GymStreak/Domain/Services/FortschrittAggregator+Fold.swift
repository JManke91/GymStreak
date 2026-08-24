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
    /// own series for the same usage — except for a partly snapshotted counterweight series,
    /// where the two pick the value space differently (per session here, series-wide there;
    /// pre-existing, see `docs/progress-charts.md` and ticket 08). It used to fold to the best estimated
    /// 1RM — which is a **Pro-gated metric** (`ProFeatureCaps.freeChartMetric` is
    /// `.maxWeight`), so the list handed every free user a number they could not read on
    /// the screen it opens. See `docs/progress-charts.md`.
    ///
    /// A row whose sets carry nothing comparable still yields a value of 0 with
    /// `hasValue == false`, which is what keeps the workout counted.
    static func foldSets(
        of workoutExercise: WorkoutExercise,
        in session: WorkoutSession
    ) -> SessionFold {
        let behavior = workoutExercise.loadBehavior
        let canUseEffectiveLoad = !behavior.isCounterweightAssistance || session.bodyWeightKg != nil
        var fold = SessionFold(isEffectiveLoad: canUseEffectiveLoad)

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
                // Heavier is the better set. `value` starts at 0 and an effective weight is
                // never negative, so plain max also covers the first recorded set.
                fold.record(max(fold.value, effective))
            } else if behavior.isCounterweightAssistance {
                // Raw assistance without a body-mass snapshot: *least*
                // assistance is the better set, so fold with min.
                fold.record(fold.hasValue ? min(fold.value, weight) : weight)
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
        var sessionValues: [(date: Date, value: Double, isEffectiveLoad: Bool)] = []
    }

    /// A single session's folded value for one usage. `hasValue` distinguishes
    /// "no comparable set yet" from a legitimately recorded 0 (an assisted set
    /// performed with no counterweight at all), which the min-fold must keep.
    struct SessionFold {
        var value: Double = 0
        var hasValue = false
        let isEffectiveLoad: Bool

        mutating func record(_ newValue: Double) {
            value = newValue
            hasValue = true
        }
    }
}
