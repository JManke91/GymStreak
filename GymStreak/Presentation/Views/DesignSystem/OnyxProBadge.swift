//
//  OnyxProBadge.swift
//  GymStreak
//
//  The marker that an entry point leads somewhere gated.
//  See docs/monetization-strategy.md §8 and docs/pro-subscription.md.
//

import SwiftUI

/// How much of the badge to draw.
enum OnyxProBadgeStyle {
    /// Lock glyph plus the "PRO" wordmark. The default.
    case labeled
    /// Lock glyph only — for tight rows where the wordmark would not fit.
    case icon
}

/// A small marker placed on an entry point that leads to gated capability.
///
/// **Never inside an active workout.** §8's absolute prohibition covers Pro
/// badges, not just paywalls: no badge in the workout session, on the watch app,
/// or on the rest-timer Live Activity.
struct OnyxProBadge: View {

    var style: OnyxProBadgeStyle = .labeled

    var body: some View {
        content
            .foregroundStyle(DesignSystem.Colors.textOnTint)
            .padding(.horizontal, style == .labeled ? 7 : 5)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(DesignSystem.Colors.tint)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("pro.badge.accessibility".localized)
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .labeled:
            HStack(spacing: 3) {
                lockGlyph
                Text("pro.badge.label".localized)
                    .font(.onyxCaption2.bold())
            }
        case .icon:
            lockGlyph
        }
    }

    private var lockGlyph: some View {
        Image(systemName: "lock.fill")
            .font(.onyxCaption2.bold())
    }
}

// MARK: - Previews

#Preview("Pro badge — dark") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        VStack(spacing: DesignSystem.Spacing.lg) {
            OnyxProBadge()
            OnyxProBadge(style: .icon)

            HStack(spacing: DesignSystem.Spacing.sm) {
                Text("Exercise Deep-Dive")
                    .font(.onyxSubheadline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                OnyxProBadge()
            }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Pro badge — light") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        HStack(spacing: DesignSystem.Spacing.sm) {
            OnyxProBadge()
            OnyxProBadge(style: .icon)
        }
        .padding()
    }
    .preferredColorScheme(.light)
}

#Preview("Pro badge — large type") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        HStack(spacing: DesignSystem.Spacing.sm) {
            Text("Period Recap")
                .font(.onyxSubheadline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            OnyxProBadge()
        }
        .padding()
    }
    .dynamicTypeSize(.accessibility1)
    .preferredColorScheme(.dark)
}
