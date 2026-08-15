//
//  MeteredAISurface.swift
//  GymStreak
//
//  The three AI surfaces that carry a free monthly taster allowance.
//  See docs/monetization-strategy.md §4.2a (P3/P4/P5) and §4.3, and
//  docs/pro-subscription.md §5e.
//

import Foundation

/// An AI surface whose free tier is *metered per calendar month* rather than
/// blocked outright.
///
/// One enum for all three, because the taster mechanic is identical — only the
/// limit and the placement differ — and §9's skipped Phase 0 means all three
/// limits will be retuned from post-launch data. A per-surface counter type
/// would make that retune three edits instead of one.
///
/// `rawValue` is a **storage key**: it is what the month-keyed counters are
/// filed under in App Group `UserDefaults` and in iCloud KVS. Renaming a case
/// does not fail — it silently orphans the user's consumed count and hands them
/// a fresh allowance, which is why the raw values are written out rather than
/// derived from the case name.
///
/// Deliberately *not* the same type as `PaywallPlacement`: only three of the
/// nine placements are metered, and a placement is "where a paywall came from"
/// while this is "what is being counted".
enum MeteredAISurface: String, CaseIterable, Sendable {

    /// P3 — Coach Chat. The counting unit is a **sent message**, not an opened
    /// screen (docs/pro-subscription.md §5e).
    case coachChat = "coach-chat"

    /// P4 — AI Period Recap. The counting unit is a fresh generation; opening a
    /// cached recap is free (ticket 09).
    case periodRecap = "period-recap"

    /// P5 — AI Exercise Deep-Dive. Same unit as the period recap (ticket 09).
    case exerciseDeepDive = "exercise-deep-dive"

    /// How many the free tier gets per calendar month. Reads `ProFeatureCaps` so
    /// every limit in the app stays retunable in one file (§4).
    var freeMonthlyLimit: Int {
        switch self {
        case .coachChat: ProFeatureCaps.freeCoachChatMessagesPerMonth
        case .periodRecap: ProFeatureCaps.freePeriodRecapsPerMonth
        case .exerciseDeepDive: ProFeatureCaps.freeExerciseDeepDivesPerMonth
        }
    }

    /// The paywall this surface raises once its allowance is spent (§8 C).
    var placement: PaywallPlacement {
        switch self {
        case .coachChat: .coachChat
        case .periodRecap: .periodRecap
        case .exerciseDeepDive: .exerciseDeepDive
        }
    }

    /// Where the month-keyed count is filed, in both stores. Namespaced under
    /// `pro.` like every other monetization key.
    var storageKey: String { "pro.allowance.\(rawValue)" }
}
