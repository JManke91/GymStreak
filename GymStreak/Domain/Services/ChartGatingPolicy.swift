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

    /// The narrowest window this user is allowed to read that still reaches the given
    /// date — what the exercise detail screen opens on, instead of always opening on 1M.
    ///
    /// The caller decides *which* date matters and in what order; this only answers
    /// "narrowest unlocked window reaching it" for one of them (see
    /// `ExerciseProgressViewModel.applyOpeningTimeframe`).
    ///
    /// `ChartTimeframe.allCases` is narrowest-first, so `first(where:)` *is* the
    /// "narrowest that works" rule: someone who trained yesterday opens on 1W rather
    /// than on the widest window that happens to contain the data, which would flatten
    /// the curve they came to see.
    ///
    /// `.all` is a legitimate candidate for a user entitled to it — its `startDate` is
    /// `distantPast`, so it is the last resort that matches anything, and for an exercise
    /// last trained over a year ago it is the only window that draws the curve at all. It
    /// costs no more to fetch than any other: the exercise fetch is unbounded by design
    /// and the window is applied in Swift afterwards (see `docs/progress-charts.md`).
    ///
    /// A locked window is skipped, never widened into: auto-selecting a Pro window
    /// would open a free user on a blurred paywall chart, which is worse than an empty
    /// one. With gating on the search therefore stops at the widest free window and
    /// returns `nil` for anything older — the caller keeps its own default and the dated
    /// empty copy explains what it is looking at.
    ///
    /// `now` is a parameter rather than a `Date()` read inside the loop, so this stays a
    /// pure function of its arguments like everything else here and its boundaries can be
    /// pinned exactly.
    static func narrowestUnlockedTimeframe(
        reaching date: Date,
        isPro: Bool,
        isGatingEnabled: Bool,
        now: Date = Date(),
        freeTimeframes: [ChartTimeframe] = ProFeatureCaps.freeChartTimeframes
    ) -> ChartTimeframe? {
        ChartTimeframe.allCases.first { timeframe in
            !isTimeframeLocked(
                timeframe,
                isPro: isPro,
                isGatingEnabled: isGatingEnabled,
                freeTimeframes: freeTimeframes
            ) && timeframe.startDate(from: now) <= date
        }
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
