//
//  SubscriptionSettingsSectionView.swift
//  GymStreak
//
//  The Settings section that states the user's plan — Founder, Pro or Free —
//  and opens the Customer Center. See docs/pro-subscription.md §5i and §5j.
//

import SwiftUI

/// Reports the current entitlement, where it came from, and the one thing there
/// is to do about it.
///
/// **Status, one purchase entry point, and the Customer Center.**
/// Restore, manage-subscription, cancellation and refund requests are not
/// hand-built here: `CustomerCenterSettingsRow` presents `RevenueCatUI`'s
/// `CustomerCenterView`, which handles all four. A Founder is offered no
/// Customer Center — they are not a RevenueCat customer at all
/// (`showsCustomerCenter`).
///
/// **The free tier's two rows were added late, and both are rejection fixes.**
/// Until 1.1.10 this section sold nothing at all — the paywall was reachable
/// only from a gate, and every gate needs data a fresh install does not have
/// (three routines, a chart with history, an exhausted AI allowance). The one
/// action a free user had was the Customer Center, which for someone who has
/// never bought anything opens on **"No subscriptions found"**. App Review took
/// that path twice, concluded there was no working purchase, rejected under
/// Guideline 2.1(b), and attached a screenshot of that screen. See
/// `appstore-rejection-1.1.9.md` §3.7 and §3.9.
///
/// The upgrade row is a single quiet row shown only to free users, not a
/// recurring upsell: `monetization-strategy.md` §8's rule is that the app never
/// *interrupts* to sell, and an entry point the user has to go looking for does
/// not interrupt anything.
///
/// It renders nothing while the kill switch is off (`SubscriptionStatusSummary`
/// returns `nil`), which is what kept the Settings screen unchanged in every
/// shipping build before ticket 15 flipped the switch on.
///
/// Reads `entitlements.state` straight out of `body`: the provider is
/// `@Observable`, so a purchase, a restore or a lapse rewrites this section with
/// no refetch and no relaunch. That read is free by the main-thread rules — no
/// collection walk, no formatter, no SwiftData relationship.
struct SubscriptionSettingsSectionView: View {

    let entitlements: any ProEntitlementProviding

    /// Raises the paywall for the upgrade row. The same seam every gate uses, so
    /// the kill switch, Rule 3 and the entitlement check all still apply — a
    /// Settings row is not a way around `PaywallPresenter`.
    let paywalls: any PaywallPresenting

    /// Injected for the same reason every other gate injects it — see
    /// `SubscriptionStatusSummary`.
    var isGatingEnabled: Bool = ProGating.isEnabled

    var body: some View {
        if let summary = SubscriptionStatusSummary(
            state: entitlements.state,
            isGatingEnabled: isGatingEnabled
        ) {
            SettingsSectionView(
                header: "settings.section.subscription".localized,
                footer: summary.footerKey.localized
            ) {
                SettingsRowView(
                    icon: summary.icon,
                    iconTint: summary.isPro
                        ? DesignSystem.Colors.tint
                        : DesignSystem.Colors.textSecondary,
                    title: summary.titleKey.localized,
                    subtitle: summary.detailKey.localized,
                    isLast: !summary.showsUpgradeAction
                        && !summary.showsRestoreAction
                        && !summary.showsCustomerCenter
                )
                .accessibilityIdentifier("settings-row-subscription")

                if summary.showsUpgradeAction {
                    SettingsActionRowView(
                        icon: "sparkles",
                        iconTint: DesignSystem.Colors.tint,
                        title: "settings.subscription.upgrade.title".localized,
                        subtitle: "settings.subscription.upgrade.subtitle".localized,
                        isLast: !summary.showsRestoreAction && !summary.showsCustomerCenter
                    ) {
                        paywalls.present(.settingsUpgrade)
                    }
                    .accessibilityIdentifier("settings-row-upgrade-to-pro")
                }

                if summary.showsRestoreAction {
                    RestorePurchasesSettingsRow(
                        entitlements: entitlements,
                        isLast: !summary.showsCustomerCenter
                    )
                }

                if summary.showsCustomerCenter {
                    CustomerCenterSettingsRow(entitlements: entitlements)
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
/// Pins each plan without a Data-layer provider — the preview's whole point is
/// the four states side by side, which no real entitlement can produce. Declared
/// at file scope (and out of release builds) because `ProEntitlementProviding`
/// is an `AnyObject` protocol, so the stand-in has to be a class.
@MainActor
private final class PreviewPinnedEntitlements: ProEntitlementProviding {
    let state: ProEntitlementState
    var isPro: Bool { state.isPro }
    init(state: ProEntitlementState) { self.state = state }
    func refresh() async {}
    func restorePurchases() async -> ProRestoreOutcome { .nothingFound }
}

/// Inert presenter: the preview is about which rows appear, not what they do.
@MainActor
private final class PreviewInertPaywalls: PaywallPresenting {
    var pendingPlacement: PaywallPlacement?
    func present(_ placement: PaywallPlacement) {}
    func sheetDidAppear() {}
    func didPresent(_ placement: PaywallPlacement) {}
    func dismiss() {}
    func hasPresented(_ placement: PaywallPlacement) -> Bool { false }
}

#Preview("Subscription section") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        ScrollView {
            VStack(spacing: 0) {
                // A bounded literal set of four, so a plain stack is correct.
                ForEach(ProEntitlementState.allCases, id: \.self) { state in
                    SubscriptionSettingsSectionView(
                        entitlements: PreviewPinnedEntitlements(state: state),
                        paywalls: PreviewInertPaywalls(),
                        isGatingEnabled: true
                    )
                }
            }
        }
    }
    .preferredColorScheme(.dark)
}
#endif
