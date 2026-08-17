//
//  DebugProStoreSectionView.swift
//  GymStreak
//
//  Debug-only Settings section that buys and restores the real RevenueCat
//  products, so the purchase path is exercisable before the paywall exists.
//  Compiled out of release builds. See docs/pro-subscription.md §3b.
//

#if DEBUG
import SwiftUI

/// Lists the store's Pro products with a Buy action, plus Restore.
///
/// This is the ticket-03 stand-in for the paywall (ticket 14): the purchase
/// *path* has to be verifiable — a real Test Store purchase flipping the
/// entitlement is the only thing that proves the entitlement identifier is
/// right — while the purchase *UI* is still a later ticket. Developer-facing, so
/// the strings are not localized.
struct DebugProStoreSectionView: View {

    let entitlements: any ProEntitlementDebugging

    @State private var products: [ProPurchaseOption] = []
    @State private var isBusy = false
    /// Last failure, shown in the footer. Cancelling never sets this — it is not
    /// an error and must produce no error UI.
    @State private var failure: String?

    var body: some View {
        SettingsSectionView(header: "Debug — Store", footer: footer) {
            // Bounded literal set (three products), so a plain stack is fine.
            ForEach(products) { product in
                SettingsRowView(
                    icon: "cart",
                    iconTint: DesignSystem.Colors.warning,
                    title: product.displayName,
                    subtitle: product.id,
                    value: product.price
                ) {
                    Button("Buy") { buy(product) }
                        .buttonStyle(.borderless)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.tint)
                        .disabled(isBusy)
                }
            }

            SettingsRowView(
                icon: "arrow.clockwise",
                iconTint: DesignSystem.Colors.warning,
                title: "Restore purchases",
                subtitle: products.isEmpty ? "No products loaded" : nil,
                isLast: true
            ) {
                Button("Restore") { restore() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.tint)
                    .disabled(isBusy)
            }
        }
        .task { products = await entitlements.availableProducts() }
    }

    /// Always names the backend first. An empty product list looks identical
    /// whichever backend produced it, and the causes are completely different —
    /// see §9.4a's failure table, which this footer points at.
    private var footer: String {
        let backend = "Backend: \(entitlements.storeBackendDescription)."

        if let failure {
            return "\(backend) Purchase failed: \(failure)"
        }
        if products.isEmpty {
            return entitlements.isUsingTestStore
                ? "\(backend) No products — offline, or nothing configured in RevenueCat."
                : """
                \(backend) No products — the simulator cannot reach the sandbox, the Paid \
                Applications Agreement is not active, or the identifiers are not configured. \
                See docs/pro-subscription.md §9.4a.
                """
        }
        return entitlements.isUsingTestStore
            ? "\(backend) Purchases are simulated, cost nothing, and grant the real entitlement."
            : "\(backend) On a device signed into a Sandbox Apple Account these are real StoreKit purchases."
    }

    private func buy(_ product: ProPurchaseOption) {
        isBusy = true
        Task {
            let result = await entitlements.purchase(product)
            // `.cancelled` deliberately clears the failure instead of setting
            // one: dismissing the sheet is a decision, not an error.
            failure = if case .failed(let message) = result { message } else { nil }
            isBusy = false
        }
    }

    private func restore() {
        isBusy = true
        Task {
            await entitlements.restorePurchases()
            isBusy = false
        }
    }
}

#Preview("Debug store") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        DebugProStoreSectionView(entitlements: PreviewProEntitlementProvider())
    }
    .preferredColorScheme(.dark)
}
#endif
