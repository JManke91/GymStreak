//
//  DebugPaywallSectionView.swift
//  GymStreak
//
//  Debug-only Settings section that raises every §8 placement, so the
//  presentation seam and the placement taxonomy are verifiable before a real
//  paywall exists. Compiled out of release builds.
//  See docs/pro-subscription.md.
//

#if DEBUG
import SwiftUI

/// One row per placement, each raising it.
///
/// It goes through `presentIgnoringEligibility`, because the shipped
/// `present(_:)` is inert while `ProGating.isEnabled` is off — which is how the
/// app ships until ticket 15 — so the ordinary path would show nothing at all.
/// Rule 3 is *not* bypassed: even here nothing presents during a workout.
/// Developer-facing, so the strings are not localized.
struct DebugPaywallSectionView: View {

    let paywalls: any PaywallPresentationDebugging
    /// The armed record behind A and B. Reset together with the once-ever
    /// record: clearing only the latter would leave both triggers still armed,
    /// so they would re-fire at the next routine creation or session end — which
    /// looks like the reset worked but proves nothing about the triggers.
    let triggers: any ProactivePaywallTrackingDebugging

    var body: some View {
        SettingsSectionView(
            header: "Debug — Paywall placements",
            footer: "Raises a placement ignoring the kill switch, the entitlement and the once-ever cap. Never presents during an active workout (Rule 3)."
        ) {
            // Bounded literal set (nine placements), so a plain stack is fine.
            ForEach(PaywallPlacement.allCases) { placement in
                SettingsRowView(
                    icon: icon(for: placement),
                    iconTint: DesignSystem.Colors.warning,
                    title: placement.identifier,
                    subtitle: subtitle(for: placement)
                ) {
                    Button("Show") { paywalls.presentIgnoringEligibility(placement) }
                        .buttonStyle(.borderless)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.tint)
                }
            }

            SettingsRowView(
                icon: "arrow.counterclockwise",
                iconTint: DesignSystem.Colors.warning,
                title: "Reset once-ever placements",
                subtitle: "Clears the fired record and disarms A and B",
                isLast: true
            ) {
                Button("Reset") {
                    paywalls.resetPresentedPlacements()
                    triggers.resetTriggers()
                }
                    .buttonStyle(.borderless)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.tint)
            }
        }
    }

    private func icon(for placement: PaywallPlacement) -> String {
        switch placement.kind {
        case .soft: "hand.wave"
        case .valueMoment: "sparkles"
        case .contextualGate: "lock"
        }
    }

    /// Names the §8 row, and for the two one-shot placements whether the record
    /// says they already fired — otherwise "nothing happened" and "already
    /// spent" look identical.
    private func subtitle(for placement: PaywallPlacement) -> String {
        switch placement.kind {
        case .soft, .valueMoment:
            let row = placement.kind == .soft ? "A" : "B"
            return "\(row) · once ever · \(paywalls.hasPresented(placement) ? "already fired" : "not yet fired")"
        case .contextualGate:
            return "C · contextual gate"
        }
    }
}
#endif
