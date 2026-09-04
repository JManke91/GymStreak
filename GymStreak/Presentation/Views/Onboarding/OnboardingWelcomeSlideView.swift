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
        RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusLG)
            .fill(DesignSystem.Colors.tint.opacity(0.15))
            .frame(width: 64, height: 64)
            .overlay {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.tint)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Check bullet

/// One "the app does this" line: a tinted checkmark and a label.
private struct CheckBullet: View {

    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.tint)

            Text(text)
                .font(.onyxSubheadline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
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
