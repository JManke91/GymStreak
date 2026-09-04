//
//  OnboardingWelcomeSlideView.swift
//  GymStreak
//
//  Step 1 of the first-run tour: what Gym Streak is, in five seconds.
//  See docs/onboarding.md.
//

import SwiftUI

/// The welcome slide.
///
/// Purely presentational — it holds no dependency and no state, so the cover
/// around it owns every decision about where the user goes next. It names the
/// three things the app does rather than selling anything: this is the top of
/// the aha path (`monetization-strategy.md` §3 Rule 1), and nothing on it is
/// gated.
struct OnboardingWelcomeSlideView: View {

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
            iconTile

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                Text("onboarding.welcome.eyebrow".localized)
                    .font(.onyxMonoLabel)
                    .tracking(2.0)
                    .foregroundStyle(DesignSystem.Colors.tint)

                Text("onboarding.welcome.title".localized)
                    .font(.onyxDisplay)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("onboarding.welcome.body".localized)
                    .font(.onyxBody)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // A bounded literal set of three, so a plain `VStack` is correct.
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                CheckBullet(text: "onboarding.welcome.bullet1".localized)
                CheckBullet(text: "onboarding.welcome.bullet2".localized)
                CheckBullet(text: "onboarding.welcome.bullet3".localized)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Icon tile

    private var iconTile: some View {
        RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusXL)
            .fill(DesignSystem.Colors.tint.opacity(0.14))
            .frame(width: 62, height: 62)
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusXL)
                    .strokeBorder(DesignSystem.Colors.tint.opacity(0.36), lineWidth: 1)
            }
            .overlay {
                // The outlined weight, not `dumbbell.fill`: the tile is a light
                // tinted wash and a solid glyph turns it into a button.
                Image(systemName: "dumbbell")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.tint)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Check bullet

/// One "the app does this" line: a tinted checkmark and a label.
private struct CheckBullet: View {

    let text: String

    /// The chip scales with the label beside it. Fixed sizes here would leave an
    /// 18pt disc next to text 2.5× that size at AX5 — the mistake
    /// `FounderCelebrationView` already solves the same way.
    @ScaledMetric(relativeTo: .footnote) private var chipSize: CGFloat = 18
    @ScaledMetric(relativeTo: .footnote) private var glyphSize: CGFloat = 9
    @ScaledMetric(relativeTo: .footnote) private var baselineInset: CGFloat = 4

    var body: some View {
        // `alignmentGuide`'s `computeValue` is `@Sendable` and `nonisolated` in the
        // SDK — SwiftUI runs it during layout, off this view's actor. Reading
        // `baselineInset` (a MainActor-isolated `@ScaledMetric` on `self`) from
        // inside it captures `self` across that boundary. Snapshotting the CGFloat
        // here, on the main actor, is what the closure is meant to receive: it then
        // captures a `Sendable` value and nothing else. See CLAUDE.md §4a —
        // outbound closure boundaries are where a green build still traps at runtime.
        let scaledBaselineInset = baselineInset

        return HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
            // A tinted chip with a thin check, not a solid `checkmark.circle.fill`:
            // three filled accent discs stacked in a column pull the eye off the
            // headline, which is what the slide is actually selling.
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.tint.opacity(0.14))
                    .overlay {
                        Circle().strokeBorder(DesignSystem.Colors.tint.opacity(0.34), lineWidth: 1)
                    }

                Image(systemName: "checkmark")
                    .font(.system(size: glyphSize, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.tint)
            }
            .frame(width: chipSize, height: chipSize)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - scaledBaselineInset }

            Text(text)
                .font(.onyxFootnote)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()
        OnboardingWelcomeSlideView()
            .padding(DesignSystem.Spacing.xl)
    }
    .preferredColorScheme(.dark)
}
