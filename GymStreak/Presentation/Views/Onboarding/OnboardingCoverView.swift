//
//  OnboardingCoverView.swift
//  GymStreak
//
//  The first-run tour: the chrome every step shares, and the step it is showing.
//  See docs/onboarding.md.
//

import SwiftUI

/// The full-screen onboarding cover.
///
/// It owns the chrome and nothing else: the segmented progress bar with Back and
/// Skip above, the call to action with the step counter below, and in between
/// whichever slide the view model's current step names. Slides are separate
/// views that know nothing about the flow — they render, the cover navigates.
///
/// The view model is passed in rather than created here, because it is
/// app-lifetime state (the host binds its `.fullScreenCover` to the same
/// instance) and because that is what makes a dismissal spend the once-ever
/// record exactly once.
struct OnboardingCoverView: View {

    let viewModel: OnboardingFlowViewModel

    var body: some View {
        VStack(spacing: 0) {
            header

            slide
                // A fresh identity per step, which is what puts the new slide at
                // the top of its scroll: the scroll offset belongs to the
                // `ScrollView`, so re-identifying it is the reset. It applies
                // going back as well as forward.
                .id(viewModel.currentStep)

            footer
        }
        .background(DesignSystem.Colors.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            Button {
                HapticManager.shared.light()
                withAnimation(DesignSystem.Animation.easeOut) { viewModel.goBack() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(
                        viewModel.canGoBack
                            ? DesignSystem.Colors.textSecondary
                            : DesignSystem.Colors.textDisabled
                    )
                    .frame(width: 32, height: 32, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canGoBack)
            .accessibilityLabel("onboarding.back.accessibility".localized)

            OnboardingProgressBar(
                stepNumber: viewModel.stepNumber,
                stepCount: viewModel.stepCount
            )

            Button {
                HapticManager.shared.light()
                viewModel.skip()
            } label: {
                Text("onboarding.skip".localized)
                    .font(.onyxCaption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignSystem.Spacing.xl)
        .padding(.top, DesignSystem.Spacing.lg)
        .padding(.bottom, DesignSystem.Spacing.md)
    }

    // MARK: - Slide

    /// The step's own content, scrollable so German copy at accessibility type
    /// sizes overflows downwards instead of being truncated — the same trade
    /// `FounderCelebrationView` makes, with the CTA pinned below.
    private var slide: some View {
        ScrollView {
            Group {
                switch viewModel.currentStep {
                case .welcome:
                    OnboardingWelcomeSlideView()
                default:
                    // Filled in by the remaining slide tickets. The chrome and
                    // the navigation are complete around them.
                    Color.clear.frame(height: 1)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.xl)
            .padding(.top, DesignSystem.Spacing.xl)
            .padding(.bottom, DesignSystem.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // `.onyxProminent` rather than `OnyxButton`, whose fixed 50pt height
            // clips a wrapped label at accessibility type sizes.
            Button {
                HapticManager.shared.light()
                withAnimation(DesignSystem.Animation.easeOut) { viewModel.advance() }
            } label: {
                Text(viewModel.currentStep.ctaKey.localized)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.onyxProminent)

            Text("onboarding.step_counter".localized(viewModel.stepNumber, viewModel.stepCount))
                .font(.onyxMonoLabel)
                .tracking(1.5)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, DesignSystem.Spacing.xl)
        .padding(.top, DesignSystem.Spacing.md)
        .padding(.bottom, DesignSystem.Spacing.lg)
    }
}

// MARK: - Progress bar

/// One capsule per step, filled up to and including the current one.
///
/// A bounded literal set — the flow's length is fixed at compile time — so a
/// plain `HStack` is the right container here.
private struct OnboardingProgressBar: View {

    let stepNumber: Int
    let stepCount: Int

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            ForEach(1...stepCount, id: \.self) { step in
                Capsule()
                    .fill(
                        step <= stepNumber
                            ? DesignSystem.Colors.tint
                            : DesignSystem.Colors.border
                    )
                    .frame(height: 4)
            }
        }
        .animation(DesignSystem.Animation.easeOut, value: stepNumber)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("onboarding.progress.accessibility".localized(stepNumber, stepCount))
    }
}

#Preview {
    OnboardingCoverView(
        viewModel: OnboardingFlowViewModel(
            // A throwaway suite, so tapping through the preview cannot record the
            // real "already onboarded" flag on the simulator.
            completion: OnboardingCompletionStore(
                defaults: UserDefaults(suiteName: "preview.onboarding") ?? .standard
            )
        )
    )
}
