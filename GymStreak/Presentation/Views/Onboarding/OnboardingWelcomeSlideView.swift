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
                OnboardingCheckBullet(text: "onboarding.welcome.bullet1".localized)
                OnboardingCheckBullet(text: "onboarding.welcome.bullet2".localized)
                OnboardingCheckBullet(text: "onboarding.welcome.bullet3".localized)
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

#Preview {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()
        OnboardingWelcomeSlideView()
            .padding(DesignSystem.Spacing.xl)
    }
    .preferredColorScheme(.dark)
}
