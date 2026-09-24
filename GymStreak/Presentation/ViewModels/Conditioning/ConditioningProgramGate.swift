//
//  ConditioningProgramGate.swift
//  GymStreak
//
//  P12's gate: how deep into the 12-week conditioning program this user may go,
//  and the one place that raises its paywall. See docs/pro-subscription.md §5l
//  and docs/fight-conditioning.md.
//

import Foundation

/// Answers "may this user have the plan for this program week?" and owns the
/// consequence of a no: raising `PaywallPlacement.conditioningProgram`.
///
/// It exists as its own type rather than as five members on
/// `ConditioningProgramViewModel` for the reason `AICoachAllowanceGate` does —
/// the ViewModel is already the program's dashboard, its watch offer and its
/// post-workout add-on, and folding a third dependency set into it made it the
/// place two unrelated questions were answered. Here the entitlement, the
/// paywall seam and the kill switch stay together and private, and the ViewModel
/// holds one collaborator instead of three.
///
/// The *rule* is not here: `ConditioningProgramGatingPolicy` (`Domain/Services/`)
/// is the pure decision, and this type is what supplies it with an entitlement
/// and acts on the answer.
@MainActor
final class ConditioningProgramGate {

    private let entitlements: any ProEntitlementProviding
    private let paywalls: any PaywallPresenting
    private let isGatingEnabled: Bool
    private var entitlementObserver: EntitlementChangeObserver?

    /// - Parameter isGatingEnabled: injected rather than read from `ProGating`
    ///   inside the checks, for the same reason `AICoachAllowanceGate` and
    ///   `PaywallPresenter` inject it: with the shipped switch baked in, every
    ///   test would pass by proving the gate is inert.
    init(
        entitlements: any ProEntitlementProviding,
        paywalls: any PaywallPresenting,
        isGatingEnabled: Bool = ProGating.isEnabled
    ) {
        self.entitlements = entitlements
        self.paywalls = paywalls
        self.isGatingEnabled = isGatingEnabled
    }

    /// How many program weeks a free user gets — the week-4 nudge's denominator.
    var freeWeeks: Int { ProFeatureCaps.freeConditioningProgramWeeks }

    /// `true` when this week's plan is Pro-only for this user. `nil` — no week
    /// in progress — is never locked: there is no plan to withhold.
    ///
    /// Reads `entitlements.isPro` on every call rather than caching it, which is
    /// what lets a view call this from `body` and have a completed purchase
    /// unblur the plan on the spot (docs/pro-subscription.md §3c).
    func isLocked(week: Int?) -> Bool {
        guard let week else { return false }
        return ConditioningProgramGatingPolicy.isWeekLocked(
            week,
            isPro: entitlements.isPro,
            isGatingEnabled: isGatingEnabled
        )
    }

    /// `true` in the last week a gated user gets for free — §8 placement D's cue
    /// to announce the wall a week before it arrives.
    func isLastFreeWeek(week: Int?) -> Bool {
        guard let week else { return false }
        return ConditioningProgramGatingPolicy.isLastFreeWeek(
            week,
            isPro: entitlements.isPro,
            isGatingEnabled: isGatingEnabled
        )
    }

    /// The gate's one intent point. Nothing auto-presents — §8 requires a tap,
    /// and the presenter still decides whether the request becomes a paywall.
    func requestUnlock() {
        paywalls.present(.conditioningProgram)
    }

    /// Calls back whenever the entitlement changes.
    ///
    /// The blur needs no help — it re-reads on every render. This exists for
    /// everything the gate's answer *freezes*: the day's suggestion, the watch
    /// offer and the post-workout add-on are all computed once per refresh, so a
    /// purchase, a restore or a lapse has to trigger another one.
    func observeEntitlementChanges(_ handler: @escaping @MainActor () -> Void) {
        entitlementObserver = EntitlementChangeObserver(entitlements: entitlements, onChange: handler)
    }
}
