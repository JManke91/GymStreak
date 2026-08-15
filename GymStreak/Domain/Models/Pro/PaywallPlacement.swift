//
//  PaywallPlacement.swift
//  GymStreak
//
//  Every place in the app that may ask for a paywall, named once.
//  See docs/monetization-strategy.md §8 and docs/pro-subscription.md.
//

import Foundation

/// Where a paywall request came from.
///
/// A typed enum rather than a boolean, because RevenueCat's **Placements**
/// feature keys dashboard-authored paywalls off exactly this kind of identifier
/// (`offerings.currentOffering(forPlacement:)`). The case is what ticket 14
/// hands the SDK, so paywall *content* becomes a dashboard concern while paywall
/// *triggering* stays in code where it belongs.
///
/// `rawValue` is that dashboard identifier and therefore a **wire string**:
/// renaming a case without renaming the Placement in the RevenueCat dashboard
/// silently falls back to the default offering rather than failing loudly.
///
/// `weekdaySchedule` is the one case §8's table does not spell out in its C row:
/// it is P9 in §5's gate matrix, a shipped contextual gate, and it behaves as a
/// C placement in every respect.
///
/// Two §8 entries deliberately have no case:
/// - **Placement D (cap-approach nudge)** is not a paywall. It is an inline,
///   non-blocking hint owned by the screen that shows it.
/// - **P7 (custom exercises beyond 3)** is not a shipped gate — there is no cap
///   constant for it in `ProFeatureCaps` and no gate ticket. Adding it later is
///   a case plus a headline string.
enum PaywallPlacement: String, CaseIterable, Identifiable, Sendable {

    // MARK: §8 A — soft, dismissible in one tap, once ever

    case firstRoutineCreated = "first-routine-created"

    // MARK: §8 B — the endowed-progress value moment, once ever

    case valueMoment = "value-moment"

    // MARK: §8 C — contextual gates, one per gated capability

    case routineCap = "routine-cap"
    case chartMetric = "chart-metric"
    case chartWindow = "chart-window"
    case coachChat = "coach-chat"
    case periodRecap = "period-recap"
    case exerciseDeepDive = "exercise-deep-dive"
    case weekdaySchedule = "weekday-schedule"

    var id: String { rawValue }

    /// The RevenueCat Placement identifier. Spelled as its own property so a
    /// call site reads as intent rather than as "the raw value happens to be it".
    var identifier: String { rawValue }

    /// Which §8 row a placement belongs to. It decides the frequency cap and,
    /// from ticket 14 on, which offering the dashboard serves.
    enum Kind: Sendable {
        /// §8 A — soft and dismissible, after the first routine is created.
        case soft
        /// §8 B — shown after a measurable value moment. The highest-value
        /// placement in the app.
        case valueMoment
        /// §8 C — raised by a specific gate, on genuine intent only.
        case contextualGate
    }

    var kind: Kind {
        switch self {
        case .firstRoutineCreated: .soft
        case .valueMoment: .valueMoment
        case .routineCap, .chartMetric, .chartWindow, .coachChat,
             .periodRecap, .exerciseDeepDive, .weekdaySchedule: .contextualGate
        }
    }

    /// `true` for the two placements §8's frequency cap says fire **once each,
    /// ever**. Contextual gates fire whenever the user hits them again.
    var isOneShot: Bool { kind != .contextualGate }

    /// Localization key for the headline.
    ///
    /// §8 C is explicit that a contextual gate must name the specific thing being
    /// unlocked — "Unlimited routines", never "Go Pro" — so the placement has to
    /// carry that much on its own; a caller passing a headline in would put the
    /// same copy decision in nine places. Written out per case rather than
    /// derived from `rawValue` so the keys stay greppable from the strings file.
    var headlineKey: String {
        switch self {
        case .firstRoutineCreated: "paywall.headline.first_routine_created"
        case .valueMoment: "paywall.headline.value_moment"
        case .routineCap: "paywall.headline.routine_cap"
        case .chartMetric: "paywall.headline.chart_metric"
        case .chartWindow: "paywall.headline.chart_window"
        case .coachChat: "paywall.headline.coach_chat"
        case .periodRecap: "paywall.headline.period_recap"
        case .exerciseDeepDive: "paywall.headline.exercise_deep_dive"
        case .weekdaySchedule: "paywall.headline.weekday_schedule"
        }
    }
}
