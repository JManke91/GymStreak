//
//  ProFeatureCaps.swift
//  GymStreak
//
//  Every free-tier limit, in one place. See docs/monetization-strategy.md §4.2a
//  and docs/pro-subscription.md.
//

import Foundation

/// The free tier's capacity and taster limits.
///
/// These live together and are named because §9 skipped the instrumentation
/// phase: there is no analytics backend to tune them against before launch, so
/// retuning any of them post-launch (the routine cap in particular — §4.4 calls
/// it "the single highest-leverage number in the document" and expects a 3-vs-4
/// A/B test) must be a one-line diff, never a refactor.
enum ProFeatureCaps {

    /// Saved routine templates a free user may keep (§4.4). Starting a workout
    /// from any of them is unlimited — this counts templates, not sessions.
    static let freeRoutineLimit = 3

    /// AI Coach Chat messages per calendar month on free (P3, taster cap).
    static let freeCoachChatMessagesPerMonth = 5

    /// AI Period Recaps per calendar month on free (P4, taster cap).
    static let freePeriodRecapsPerMonth = 1

    /// AI Exercise Deep-Dives per calendar month on free (P5, taster cap).
    static let freeExerciseDeepDivesPerMonth = 1

    /// The only progress metric free users can chart (P2). Estimated 1RM and
    /// training volume are Pro.
    static let freeChartMetric: ProgressMetric = .maxWeight

    /// Chart windows available on free (P2) — up to three months. Longer
    /// windows (`.year`, `.all`) are Pro; no data is ever deleted, so the gate
    /// is fully reversible.
    static let freeChartTimeframes: [ChartTimeframe] = [.week, .month, .threeMonths]
}
