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
/// **Status, plus the Customer Center — and no purchase affordance for anyone.**
/// Restore, manage-subscription, cancellation and refund requests are not
/// hand-built here: `CustomerCenterSettingsRow` presents `RevenueCatUI`'s
/// `CustomerCenterView`, which handles all four. The section still sells
/// nothing; the paywall is the only surface that does, and it is reached from a
/// gate, never from Settings. A Founder is offered no Customer Center either —
/// they are not a RevenueCat customer at all (`showsCustomerCenter`).
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
                    isLast: !summary.showsCustomerCenter
                )
                .accessibilityIdentifier("settings-row-subscription")

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
                        isGatingEnabled: true
                    )
                }
            }
        }
    }
    .preferredColorScheme(.dark)
}
#endif
