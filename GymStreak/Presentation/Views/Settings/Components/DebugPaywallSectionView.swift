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
/// app shipped until ticket 15 — so the ordinary path showed nothing at all.
/// Still the development route after the flip: `present(_:)` now honours real
/// eligibility, so a spent one-shot or an entitled account draws nothing.
/// Rule 3 is *not* bypassed: even here nothing presents during a workout.
/// Developer-facing, so the strings are not localized.
struct DebugPaywallSectionView: View {

    let paywalls: any PaywallPresentationDebugging
    /// The armed record behind A and B. Reset together with the once-ever
    /// record: clearing only the latter would leave both triggers still armed,
    /// so they would re-fire at the next routine creation or session end — which
    /// looks like the reset worked but proves nothing about the triggers.
    let triggers: any ProactivePaywallTrackingDebugging
    /// The Founder thank-you (docs/pro-subscription.md §5h). It lives in this
    /// section because it is the same kind of thing — a once-ever screen the
    /// kill switch keeps inert — and because the Founder grant never resolves
    /// outside a production install, so this and the entitlement picker are the
    /// only ways to see it at all.
    let founderCelebration: FounderCelebrationCoordinator

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
                icon: "checkmark.seal",
                iconTint: DesignSystem.Colors.warning,
                title: "Founder celebration",
                subtitle: "Once ever · \(founderCelebration.hasCelebrated ? "already shown" : "not yet shown")"
            ) {
                Button("Show") { founderCelebration.presentIgnoringEligibility() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.tint)
            }

            SettingsRowView(
                icon: "arrow.counterclockwise",
                iconTint: DesignSystem.Colors.warning,
                title: "Reset once-ever placements",
                subtitle: "Clears the fired record, disarms A and B, un-shows the Founder screen",
                isLast: true
            ) {
                Button("Reset") {
                    paywalls.resetPresentedPlacements()
                    triggers.resetTriggers()
                    founderCelebration.resetCelebration()
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
