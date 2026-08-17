//
//  PeriodRecapAllowanceCard.swift
//  GymStreak
//
//  The two free-tier cards of the AI Period Recap (P4): the offer to spend the
//  month's single generation, and the gate once it is spent.
//  See docs/pro-subscription.md §5e.
//

import SwiftUI

/// The card `PeriodRecapView` shows a metered user in place of a narrative.
///
/// Purely presentational, like the rest of the §5b kit: it takes a finished
/// nudge value and a callback, and never sees the entitlement, the paywall
/// presenter or the ViewModel. The two modes share a body because they are the
/// same card with a different verb — collapsing them keeps the "spend it" and
/// "unlock it" affordances visually identical, which is what makes the second
/// read as the continuation of the first rather than as a different screen.
struct PeriodRecapAllowanceCard: View {

    enum Mode: Equatable {
        /// Allowance left. `periodLabel` is the range the generation would
        /// cover, passed in already formatted.
        case offer(periodLabel: String)
        /// Nothing left this month. The paywall was raised on arrival; this is
        /// the way back to it.
        case gated
    }

    let mode: Mode
    let nudge: AIAllowanceNudge?
    let onPrimaryTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if case .offer(let periodLabel) = mode {
                Text(String(format: "ai_coach.period_recap.offer.subtitle".localized, periodLabel))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // §8 placement D — sits above the button that spends the allowance,
            // so the count is on screen before the tap, not after it.
            if let nudge {
                OnyxCapNudge(text: nudge.text, used: nudge.used, limit: nudge.limit)
            }

            primaryButton
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Sub-views

    private var header: some View {
        HStack(spacing: 8) {
            switch mode {
            case .offer:
                AISparkleView(size: 18, color: AICoachTheme.accent, glow: true)
            case .gated:
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AICoachTheme.accent)
            }

            Text(headline)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
        }
    }

    private var primaryButton: some View {
        Button {
            HapticManager.shared.light()
            onPrimaryTap()
        } label: {
            Text(buttonTitle)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                // Never white on the tint colour — see CLAUDE.md's contrast rule.
                .foregroundStyle(DesignSystem.Colors.textOnTint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AICoachTheme.accent)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Copy

    private var headline: String {
        switch mode {
        case .offer: "ai_coach.period_recap.offer.title".localized
        // §8 C: a contextual gate names the specific thing being unlocked, and
        // the placement already carries that copy for every gate in the app.
        case .gated: PaywallPlacement.periodRecap.headlineKey.localized
        }
    }

    private var buttonTitle: String {
        switch mode {
        case .offer: "ai_coach.period_recap.offer.cta".localized
        case .gated: "pro.lock.cta".localized
        }
    }
}

// MARK: - Previews

#Preview("Offer") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()
        PeriodRecapAllowanceCard(
            mode: .offer(periodLabel: "August 2026"),
            nudge: AIAllowanceNudge(text: "1 of 1 free AI recaps left this month", used: 0, limit: 1),
            onPrimaryTap: {}
        )
        .padding(20)
    }
}

#Preview("Gated") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()
        PeriodRecapAllowanceCard(
            mode: .gated,
            nudge: AIAllowanceNudge(text: "No free AI recaps left this month.", used: 1, limit: 1),
            onPrimaryTap: {}
        )
        .padding(20)
    }
}
