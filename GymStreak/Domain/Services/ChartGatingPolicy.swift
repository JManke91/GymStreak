//
//  ChartGatingPolicy.swift
//  GymStreak
//
//  P2 — the free-tier progress-analytics gate, as pure logic over two flags.
//  See docs/monetization-strategy.md §4.2a P2, §3 Rule 2 and §7, and
//  docs/pro-subscription.md §5d.
//

import Foundation

/// Decides which progress metrics and chart windows a user may read.
///
/// Pure and isolation-agnostic like every other `Domain/Services` type, and it
/// produces **no user-facing text** — the lock copy comes from
/// `PaywallPlacement.headlineKey`, and `Domain/` holds no localization keys.
///
/// Nothing here hides or deletes a workout: §7's Rule 4 makes this gate purely a
/// *view* narrowing, so a lapse blurs a chart and a resubscribe unblurs it with
/// no data migration in either direction.
enum ChartGatingPolicy {

    /// `true` when the analytics gate applies to this user at all. A Founder is
    /// Pro, so this is `false` for them; with gating off it is `false` for
    /// everyone, which is what makes the shipped charts behave exactly as they
    /// did before monetization.
    static func isSubjectToGate(isPro: Bool, isGatingEnabled: Bool) -> Bool {
        isGatingEnabled && !isPro
    }

    /// `true` when this metric is Pro-only for this user.
    ///
    /// The free metric comes from `ProFeatureCaps`, never from a literal here:
    /// §4.4 and §11 Q4 both expect these to be retuned once there is data.
    static func isMetricLocked(
        _ metric: ProgressMetric,
        isPro: Bool,
        isGatingEnabled: Bool,
        freeMetric: ProgressMetric = ProFeatureCaps.freeChartMetric
    ) -> Bool {
        isSubjectToGate(isPro: isPro, isGatingEnabled: isGatingEnabled) && metric != freeMetric
    }

    /// `true` when this chart window is Pro-only for this user.
    static func isTimeframeLocked(
        _ timeframe: ChartTimeframe,
        isPro: Bool,
        isGatingEnabled: Bool,
        freeTimeframes: [ChartTimeframe] = ProFeatureCaps.freeChartTimeframes
    ) -> Bool {
        isSubjectToGate(isPro: isPro, isGatingEnabled: isGatingEnabled)
            && !freeTimeframes.contains(timeframe)
    }

    /// The widest window a gated user may read — what a chart falls back to when
    /// the window it was last showing is no longer allowed (the lapse case).
    ///
    /// "Widest" is read off `ChartTimeframe.allCases`, whose declaration order is
    /// narrowest-first; `widestFreeWindowIsThreeMonths` pins that so a reordering
    /// of the enum cannot silently narrow every lapsed user's chart.
    static func widestFreeTimeframe(
        freeTimeframes: [ChartTimeframe] = ProFeatureCaps.freeChartTimeframes
    ) -> ChartTimeframe {
        ChartTimeframe.allCases.last(where: freeTimeframes.contains) ?? .week
    }
}
