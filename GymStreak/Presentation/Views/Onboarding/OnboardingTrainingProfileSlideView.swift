//
//  OnboardingTrainingProfileSlideView.swift
//  GymStreak
//
//  Step 7 of the first-run tour: "How do you train?" — the lift-or-fight fork,
//  with the Strong / Hevy import as a side door. See docs/onboarding.md.
//

import SwiftUI

/// The last slide: one question, two answers, and a link for switchers.
///
/// Purely presentational, like every slide — the selection and both actions
/// are the cover's, handed in. There is no preview plate here on purpose: the
/// feature slides show a piece of the app, and a question has no screen to
/// picture. It keeps the tour's type scale, the eyebrow / title / body stack
/// and the tinted check chip of `OnboardingCheckBullet`, so the step reads as
/// the same tour rather than a form that was bolted on.
///
/// Nothing on it installs, imports or records anything. Selecting a card only
/// changes the CTA under it; the import link opens the same sheet Settings
/// does; the answer is written when the CTA is tapped, by the view model.
struct OnboardingTrainingProfileSlideView: View {

    let selection: OnboardingTrainingProfile
    let onSelect: (OnboardingTrainingProfile) -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
            copy

            // A bounded literal set of two, so a plain `VStack` is correct.
            VStack(spacing: DesignSystem.Spacing.md) {
                TrainingProfileOptionCard(
                    symbol: "dumbbell",
                    title: "onboarding.profile.lift.title".localized,
                    detail: "onboarding.profile.lift.detail".localized,
                    isSelected: selection == .lift
                ) { onSelect(.lift) }

                TrainingProfileOptionCard(
                    symbol: "figure.boxing",
                    title: "onboarding.profile.fight.title".localized,
                    detail: "onboarding.profile.fight.detail".localized,
                    isSelected: selection == .fight
                ) { onSelect(.fight) }
            }

            importLink
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Copy

    private var copy: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("onboarding.profile.eyebrow".localized)
                .font(.onyxMonoLabel)
                .tracking(2.0)
                .foregroundStyle(DesignSystem.Colors.tint)

            Text("onboarding.profile.title".localized)
                .font(.onyxDisplay)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("onboarding.profile.body".localized)
                .font(.onyxBody)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Import link

    /// Secondary by design: a switcher needs to find it, a new lifter must not
    /// read it as a third answer. Same accent, text weight rather than a card.
    private var importLink: some View {
        Button {
            HapticManager.shared.light()
            onImport()
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 15, weight: .semibold))
                Text("onboarding.profile.import".localized)
                    .font(.onyxSubheadline)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(DesignSystem.Colors.tint)
            .frame(minHeight: DesignSystem.Dimensions.buttonHeightCompact)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Option card

/// One answer: an icon wash, the title and a line of detail, and a check chip
/// that fills when the card is the selected one.
///
/// The icon tile is the welcome slide's tinted wash at a smaller size, and the
/// chip is `OnboardingCheckBullet`'s — unselected it is the empty ring, selected
/// it fills with the tint and the check turns `textOnTint`, which is the one
/// colour allowed on the green (CLAUDE.md, colour contrast).
private struct TrainingProfileOptionCard: View {

    let symbol: String
    let title: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    /// Scales with the title, like the bullet chip scales with its label.
    @ScaledMetric(relativeTo: .subheadline) private var chipSize: CGFloat = 22
    @ScaledMetric(relativeTo: .subheadline) private var glyphSize: CGFloat = 11

    var body: some View {
        Button {
            HapticManager.shared.selection()
            action()
        } label: {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
                iconTile

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text(title)
                        .font(.onyxHeader)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(detail)
                        .font(.onyxFootnote)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                checkChip
            }
            .padding(DesignSystem.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusXL, style: .continuous)
                    .fill(isSelected ? DesignSystem.Colors.tint.opacity(0.08) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusXL, style: .continuous)
                    .strokeBorder(
                        isSelected ? DesignSystem.Colors.tint.opacity(0.6) : DesignSystem.Colors.border,
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusXL, style: .continuous))
            .animation(DesignSystem.Animation.snappy, value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var iconTile: some View {
        RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusMD, style: .continuous)
            .fill(DesignSystem.Colors.tint.opacity(0.14))
            .frame(width: 44, height: 44)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.tint)
            }
            .accessibilityHidden(true)
    }

    private var checkChip: some View {
        ZStack {
            if isSelected {
                Circle()
                    .fill(DesignSystem.Colors.tint)
                Image(systemName: "checkmark")
                    .font(.system(size: glyphSize, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textOnTint)
            } else {
                Circle()
                    .strokeBorder(DesignSystem.Colors.border, lineWidth: 1.5)
            }
        }
        .frame(width: chipSize, height: chipSize)
        .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()
        OnboardingTrainingProfileSlideView(selection: .fight, onSelect: { _ in }, onImport: {})
            .padding(DesignSystem.Spacing.xl)
    }
    .preferredColorScheme(.dark)
}
