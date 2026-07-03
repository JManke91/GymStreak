//
//  AICoachOptInView.swift
//  GymStreak
//
//  Full-screen opt-in presented via .fullScreenCover when
//  AICoachAvailability.state == .available && !AICoachPreferences.hasCompletedOptIn.
//

import SwiftUI

/// First-run opt-in screen for the AI Coach feature.
///
/// Presented as a `.fullScreenCover`. The user can either:
/// - "Coach aktivieren" → sets `hasCompletedOptIn = true` + `isMasterEnabled = true`, dismisses.
/// - "Vielleicht später" → records the decline timestamp (7-day re-prompt cooldown), dismisses.
struct AICoachOptInView: View {

    // MARK: - Dependencies

    @Environment(\.dismiss) private var dismiss
    private let preferences = AICoachPreferences.shared

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 14)

                // MARK: Hero sparkle
                heroMark

                Spacer().frame(height: 24)

                // MARK: Headline group
                headlineGroup

                Spacer().frame(height: 28)

                // MARK: Feature rows
                featureRows

                Spacer()

                // MARK: CTAs
                ctaStack

                // MARK: Privacy footer
                privacyFooter
                    .padding(.top, 8)
                    .padding(.bottom, 30)
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Hero

    private var heroMark: some View {
        ZStack {
            // Subtle ambient glow behind the sparkle
            RadialGradient(
                gradient: Gradient(colors: [
                    DesignSystem.Colors.tint.opacity(0.18),
                    Color.clear
                ]),
                center: .center,
                startRadius: 0,
                endRadius: 80
            )
            .frame(width: 160, height: 160)
            .blur(radius: 12)

            AISparkleView(size: 88, glow: true)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Headline Group

    private var headlineGroup: some View {
        VStack(spacing: 0) {
            Text("ai_coach.optin.eyebrow".localized.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(3.0)
                .foregroundStyle(DesignSystem.Colors.tint)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 10)

            Text("ai_coach.optin.headline".localized)
                .font(.system(size: 30, weight: .heavy, design: .default))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .kerning(-0.5)

            Spacer().frame(height: 14)

            Text("ai_coach.optin.body".localized)
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
    }

    // MARK: - Feature Rows

    private var featureRows: some View {
        VStack(spacing: 0) {
            FeatureRow(
                icon: AnyView(Image(systemName: "lock.shield.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DesignSystem.Colors.tint)),
                title: "ai_coach.optin.feature1.title".localized,
                description: "ai_coach.optin.feature1.description".localized
            )

            FeatureRow(
                icon: AnyView(Image(systemName: "trophy.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DesignSystem.Colors.tint)),
                title: "ai_coach.optin.feature2.title".localized,
                description: "ai_coach.optin.feature2.description".localized
            )

            FeatureRow(
                icon: AnyView(AISparkleView(size: 18)),
                title: "ai_coach.optin.feature3.title".localized,
                description: "ai_coach.optin.feature3.description".localized
            )
        }
    }

    // MARK: - CTAs

    private var ctaStack: some View {
        VStack(spacing: 10) {
            // Primary: activate coach
            Button {
                preferences.hasCompletedOptIn = true
                preferences.isMasterEnabled = true
                dismiss()
            } label: {
                Text("ai_coach.optin.cta_primary".localized)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textOnTint) // black on green — CLAUDE.md required
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(DesignSystem.Colors.tint)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ai_coach.optin.cta_primary.accessibility".localized)

            // Secondary: maybe later
            Button {
                preferences.recordOptInDeclined()
                dismiss()
            } label: {
                Text("ai_coach.optin.cta_secondary".localized)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ai_coach.optin.cta_secondary.accessibility".localized)
        }
    }

    // MARK: - Privacy Footer

    private var privacyFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.35))

            Text("ai_coach.optin.footer".localized)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: AnyView
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DesignSystem.Colors.tint.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(DesignSystem.Colors.tint.opacity(0.2), lineWidth: 1)
                    )
                    .frame(width: 38, height: 38)

                icon
                    .frame(width: 22, height: 22)
            }
            .accessibilityHidden(true)

            // Text
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .kerning(-0.2)

                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineSpacing(2.5)
            }

            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#Preview("Opt-in") {
    AICoachOptInView()
        .preferredColorScheme(.dark)
}
