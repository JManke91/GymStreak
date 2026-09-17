//
//  WorkoutReminderOptInView.swift
//  GymStreak
//
//  The one in-app screen that offers training reminders. Only its yes button
//  can raise the iOS permission prompt. See docs/workout-reminders.md.
//

import SwiftUI

/// The soft pre-prompt in front of the system notification permission.
///
/// **It is not a paywall and must not read like one.** It arrives at the moment
/// the first-run tour used to end on a Pro offer — an offer that was retired
/// precisely because a purchase request before the user has logged a set sits in
/// front of the aha path (`docs/acquisition-strategy.md` §4.12). One screen, one
/// benefit, an obvious way out: the decline is a full-width control at the same
/// reading position as the accept, not a dimmed word in a corner.
///
/// The view model is passed in rather than created here, because it is
/// app-lifetime state — the host binds its `.fullScreenCover` to the same
/// instance, which is what makes an answer be recorded exactly once.
struct WorkoutReminderOptInView: View {

    let viewModel: WorkoutReminderOptInViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                hero
                headlineGroup
                benefits
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignSystem.Spacing.xl)
            .padding(.top, DesignSystem.Spacing.xxl)
            .padding(.bottom, DesignSystem.Spacing.lg)
        }
        // The content outgrows a compact screen at German copy and accessibility
        // type sizes; it scrolls, with the two controls pinned, rather than
        // silently compressing the body text — the same trade
        // `AICoachOptInView` makes.
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .background(DesignSystem.Colors.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .preferredColorScheme(.dark)
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack {
            Circle()
                .fill(DesignSystem.Colors.tint.opacity(0.12))
                .frame(width: 84, height: 84)

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.tint)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Headline

    private var headlineGroup: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("reminders.optin.eyebrow".localized)
                .font(.onyxMonoLabel)
                .tracking(2.5)
                .foregroundStyle(DesignSystem.Colors.tint)

            Text("reminders.optin.headline".localized)
                .font(.onyxDisplay)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("reminders.optin.body".localized)
                .font(.onyxBody)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Benefits

    /// A bounded literal set of three rows, so a plain `VStack` is the right
    /// container (main-thread rule 1 is about `ForEach` over user-scaled data).
    private var benefits: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            BenefitRow(
                symbol: "calendar",
                title: "reminders.optin.benefit1.title".localized,
                detail: "reminders.optin.benefit1.detail".localized
            )
            BenefitRow(
                symbol: "hand.raised.fill",
                title: "reminders.optin.benefit2.title".localized,
                detail: "reminders.optin.benefit2.detail".localized
            )
            BenefitRow(
                symbol: "iphone.slash",
                title: "reminders.optin.benefit3.title".localized,
                detail: "reminders.optin.benefit3.detail".localized
            )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            // `.onyxProminent` rather than `OnyxButton`, whose fixed 50pt height
            // clips a wrapped label at accessibility type sizes — the same
            // reason the tour's CTA uses it.
            Button {
                HapticManager.shared.light()
                Task { await viewModel.accept() }
            } label: {
                Text("reminders.optin.cta_primary".localized)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.onyxProminent)

            Button {
                HapticManager.shared.light()
                viewModel.decline()
            } label: {
                Text("reminders.optin.cta_secondary".localized)
                    .font(.onyxSubheadline)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: DesignSystem.Dimensions.buttonHeightCompact)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("reminders.optin.footer".localized)
                .font(.onyxCaption2)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DesignSystem.Spacing.xl)
        .padding(.top, DesignSystem.Spacing.md)
        .padding(.bottom, DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.background.ignoresSafeArea(edges: .bottom))
    }
}

// MARK: - Benefit row

private struct BenefitRow: View {

    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.lg) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.tint)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(title)
                    .font(.onyxSubheadline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(.onyxFootnote)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
