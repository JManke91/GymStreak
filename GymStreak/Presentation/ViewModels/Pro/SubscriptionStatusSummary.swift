//
//  SubscriptionStatusSummary.swift
//  GymStreak
//
//  What the Settings subscription section says about the current entitlement,
//  as a value. See docs/pro-subscription.md §5i.
//

import Foundation

/// The finished description of the user's plan: which plan it is, and the three
/// pieces of copy the Settings row is built from.
///
/// A value rather than logic inside the view, for the same reason `AIAllowanceNudge`
/// is one: the mapping from entitlement to copy is the part worth asserting, and
/// a `View` cannot be asserted against.
///
/// It carries **keys, not localized strings** — like `PaywallPlacement.headlineKey`
/// — so the mapping stays assertable without a bundle and the section view does
/// the one thing views are allowed to do with copy: look it up.
struct SubscriptionStatusSummary: Equatable {

    /// The plan as a user would name it.
    ///
    /// `subscription` and `lifetime` stay distinct even though both simply mean
    /// "Pro": telling someone who paid once that they hold a renewing
    /// subscription is a factual error about their own money, and it is exactly
    /// the distinction `ProEntitlementState` was given a source for.
    enum Plan: Equatable {
        case founder
        case subscription
        case lifetime
        case free
    }

    let plan: Plan

    /// Builds the summary, or `nil` when no subscription section belongs in
    /// Settings at all.
    ///
    /// - Parameter isGatingEnabled: injected rather than read from `ProGating`
    ///   inside the check, for the same reason `PaywallPresenter` and
    ///   `FounderCelebrationCoordinator` inject it: with the shipped switch
    ///   baked in, a test would pass by proving the section is absent rather
    ///   than that it is right.
    ///
    /// **The kill switch hides the whole section**, it does not merely soften
    /// it. While gating is off the app has no paid tier at all, and a section
    /// announcing "Free" — or thanking a Founder for an entitlement nothing is
    /// yet using — would be the one visible contradiction of
    /// `monetization-strategy.md` §7's rule that the listing copy and the
    /// paywall ship together. The release that flips the switch is the release
    /// this section appears in.
    init?(state: ProEntitlementState, isGatingEnabled: Bool = ProGating.isEnabled) {
        guard isGatingEnabled else { return nil }
        switch state {
        case .founder: plan = .founder
        case .subscription: plan = .subscription
        case .lifetime: plan = .lifetime
        case .free: plan = .free
        }
    }

    /// `true` whenever the described plan grants Pro.
    var isPro: Bool { plan != .free }

    /// Whether the section offers a way to *buy* Pro.
    ///
    /// **Free users only** — the other three plans already have it.
    ///
    /// This is the fix for the second App Store rejection
    /// (`appstore-rejection-1.1.9.md` §3.9). Before it, the section headed
    /// *Subscription* offered a free user exactly one action — the Customer
    /// Center — which for someone who has never bought anything opens on
    /// "No subscriptions found". App Review tapped it, found no way to purchase,
    /// and rejected under 2.1(b); the screenshot they attached is that screen.
    ///
    /// It sits above `showsRestoreAction`, which is the free tier's Guideline
    /// 3.1.1 path — buy first, restore second, and neither is a dead end.
    var showsUpgradeAction: Bool { plan == .free }

    /// Whether the section offers the Customer Center (§5j).
    ///
    /// **Only plans that actually have something to manage.** It used to be
    /// everyone but a Founder, on the reasoning that a free user who reinstalled
    /// needs a restore path and Guideline 3.1.1 says that path cannot be
    /// conditioned on the app already believing the user paid. The reasoning was
    /// right; the surface was wrong. Offered to a free user, the Customer Center
    /// opens on **"No subscriptions found"** — App Review took that path twice,
    /// concluded the app had no working purchase, and attached a screenshot of
    /// that very screen to the second rejection
    /// (`appstore-rejection-1.1.9.md` §3.7).
    ///
    /// A free user now gets `showsRestoreAction` instead: a row that does one
    /// thing and names it. 3.1.1 is satisfied more directly than before.
    ///
    /// A Founder gets neither. The grant is decided locally from
    /// `AppTransaction` and never round-trips to RevenueCat (§9.3), so they are
    /// not a RevenueCat customer at all and have nothing to restore or manage.
    var showsCustomerCenter: Bool { plan == .subscription || plan == .lifetime }

    /// Whether the section offers a plain **Restore purchases** row.
    ///
    /// Free users only — the Guideline 3.1.1 path, see `showsCustomerCenter`.
    var showsRestoreAction: Bool { plan == .free }

    /// SF Symbol for the row's icon tile.
    var icon: String {
        switch plan {
        case .founder: "checkmark.seal.fill"
        case .subscription: "checkmark.seal.fill"
        case .lifetime: "infinity"
        case .free: "figure.strengthtraining.traditional"
        }
    }

    var titleKey: String {
        switch plan {
        case .founder: "settings.subscription.founder.title"
        case .subscription: "settings.subscription.pro.title"
        case .lifetime: "settings.subscription.lifetime.title"
        case .free: "settings.subscription.free.title"
        }
    }

    var detailKey: String {
        switch plan {
        case .founder: "settings.subscription.founder.detail"
        case .subscription: "settings.subscription.pro.detail"
        case .lifetime: "settings.subscription.lifetime.detail"
        case .free: "settings.subscription.free.detail"
        }
    }

    /// The explanatory line under the card — where the plan came from and what,
    /// if anything, the user has to do about it.
    var footerKey: String {
        switch plan {
        case .founder: "settings.subscription.founder.footer"
        case .subscription: "settings.subscription.pro.footer"
        case .lifetime: "settings.subscription.lifetime.footer"
        case .free: "settings.subscription.free.footer"
        }
    }
}
