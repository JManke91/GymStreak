//
//  DebugProEntitlementSectionView.swift
//  GymStreak
//
//  Debug-only Settings section that simulates the Pro entitlement, so every
//  gate can be exercised without a store. Compiled out of release builds.
//  See docs/pro-subscription.md.
//

#if DEBUG
import Observation
import SwiftUI

/// Switches the *reported* entitlement between the really-resolved one, Free,
/// Pro and Founder.
///
/// The whole file is inside `#if DEBUG`: nothing in a shipping binary can write
/// an entitlement, and the strings are developer-facing so they are not
/// localized. The picker writes `simulatedState` on the shared provider, which
/// is `@Observable`, so every gate re-evaluates immediately — no app restart.
struct DebugProEntitlementSectionView: View {

    let entitlements: any ProEntitlementDebugging

    var body: some View {
        SettingsSectionView(
            header: "Debug",
            footer: gatingFooter
        ) {
            SettingsRowView(
                icon: "hammer",
                iconTint: DesignSystem.Colors.warning,
                title: "Simulated entitlement",
                subtitle: subtitle,
                isLast: true
            ) {
                Picker("", selection: selection) {
                    Text("Real").tag(ProEntitlementState?.none)
                    ForEach(Self.options, id: \.self) { option in
                        Text(title(for: option)).tag(ProEntitlementState?.some(option))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(DesignSystem.Colors.tint)
                .accessibilityIdentifier("settings-debug-entitlement-picker")
            }
        }
    }

    /// Says whether gates are live *and where that came from*, because "nothing
    /// happened" has two very different causes: the shipped switch being off, or
    /// the launch argument not being ticked in the scheme (§9.4a).
    private var gatingFooter: String {
        guard ProGating.isEnabled else {
            return """
            Debug builds only. Gating is globally OFF, so gates stay inert regardless of this \
            setting. Launch with \(ProGating.forceOnLaunchArgument) to turn them on.
            """
        }
        let source = ProGating.isForcedOnForDebugging
            ? "forced on by \(ProGating.forceOnLaunchArgument)"
            : "on in the shipped build"
        return "Debug builds only. Gating is \(source), so every gate is live."
    }

    /// Always names the really-resolved entitlement, so it is unambiguous
    /// whether the picker is reporting RevenueCat's answer or overriding it.
    private var subtitle: String {
        let resolved = "real: \(entitlements.resolvedState.rawValue)"
        guard let simulated = entitlements.simulatedState else {
            return "Reporting \(resolved)"
        }
        return "Overriding \(simulated.rawValue) — \(resolved)"
    }

    /// The three states a developer needs to see. `.lifetime` is omitted — it
    /// is indistinguishable from `.subscription` at every gate, and the Test
    /// Store section below reaches it through a real purchase.
    private static let options: [ProEntitlementState] = [.free, .subscription, .founder]

    private var selection: Binding<ProEntitlementState?> {
        Binding(
            get: { entitlements.simulatedState },
            set: { entitlements.simulatedState = $0 }
        )
    }

    private func title(for state: ProEntitlementState) -> String {
        switch state {
        case .free: "Free"
        case .subscription: "Pro"
        case .founder: "Founder"
        case .lifetime: "Pro (lifetime)"
        }
    }
}

// MARK: - Preview

/// Stand-in so the preview stays ignorant of the Data-layer provider. Declared
/// at file scope because `@Observable` cannot be attached to a type local to the
/// `#Preview` body — and without it the picker would look stuck.
@Observable
@MainActor
final class PreviewProEntitlementProvider: ProEntitlementDebugging {
    var simulatedState: ProEntitlementState?
    private(set) var resolvedState: ProEntitlementState = .free
    var state: ProEntitlementState { simulatedState ?? resolvedState }
    var isPro: Bool { state.isPro }
    func refresh() async {}

    let storeBackendDescription = "Preview (no store)"
    let isUsingTestStore = true

    func availableProducts() async -> [ProPurchaseOption] {
        [
            ProPurchaseOption(id: "monthly", displayName: "Monthly", price: "€3.99"),
            ProPurchaseOption(id: "yearly", displayName: "Yearly", price: "€29.99"),
            ProPurchaseOption(id: "lifetime", displayName: "Lifetime", price: "€79.99")
        ]
    }

    func purchase(_ option: ProPurchaseOption) async -> ProPurchaseResult {
        resolvedState = option.id == "lifetime" ? .lifetime : .subscription
        return .purchased
    }

    func restorePurchases() async {}
}

#Preview("Debug entitlement") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        DebugProEntitlementSectionView(entitlements: PreviewProEntitlementProvider())
    }
    .preferredColorScheme(.dark)
}
#endif
