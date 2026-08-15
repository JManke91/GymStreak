//
//  OnyxCapNudge.swift
//  GymStreak
//
//  Placement D — the inline, non-blocking allowance hint.
//  See docs/monetization-strategy.md §8 and docs/pro-subscription.md.
//

import SwiftUI

/// An inline hint showing how much of a free-tier allowance is consumed
/// ("2 of 3 routines used"). **This is not a paywall**: it blocks nothing, opens
/// nothing and has no CTA.
///
/// §8 placement D: showing the consumed proportion of an allowance measurably
/// lifts conversion, and it removes the surprise from the contextual gate that
/// follows it.
///
/// `text` is supplied already localized by the caller, because each gate phrases
/// its own allowance ("2 of 3 routines used", "1 message left today") and a
/// single generic format string does not survive translation into German.
/// `used` and `limit` drive the meter and the colour.
struct OnyxCapNudge: View {

    let text: String
    let used: Int
    let limit: Int

    /// Clamped so a caller that over-counts (used > limit) cannot draw a meter
    /// past full or a negative fraction.
    private var consumed: Double {
        guard limit > 0 else { return 1 }
        return min(max(Double(used), 0), Double(limit)) / Double(limit)
    }

    private var isAtCap: Bool { used >= limit }

    private var accentColor: Color {
        isAtCap ? DesignSystem.Colors.warning : DesignSystem.Colors.tint
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: isAtCap ? "exclamationmark.circle.fill" : "gauge.with.needle")
                .font(.onyxSubheadline)
                .foregroundStyle(accentColor)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(text)
                    .font(.onyxCaption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                ProgressView(value: consumed)
                    .progressViewStyle(.linear)
                    .tint(accentColor)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusMD)
                .fill(DesignSystem.Colors.card)
        )
        // A hint, never a control: it must not swallow taps meant for the
        // content it sits next to.
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

// MARK: - Previews

#Preview("Cap nudge — dark") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        VStack(spacing: DesignSystem.Spacing.lg) {
            OnyxCapNudge(text: "2 of 3 routines used", used: 2, limit: 3)
            OnyxCapNudge(text: "3 of 3 routines used", used: 3, limit: 3)
            OnyxCapNudge(text: "1 of 5 Coach messages left today", used: 4, limit: 5)
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Cap nudge — light") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        OnyxCapNudge(text: "2 of 3 routines used", used: 2, limit: 3)
            .padding()
    }
    .preferredColorScheme(.light)
}

#Preview("Cap nudge — large type") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        OnyxCapNudge(text: "1 of 5 Coach messages left today", used: 4, limit: 5)
            .padding()
    }
    .dynamicTypeSize(.accessibility1)
    .preferredColorScheme(.dark)
}
