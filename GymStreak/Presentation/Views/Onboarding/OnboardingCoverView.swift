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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The animation Back and Next change the step with — the same horizontal
    /// slide a swipe makes. With Reduce Motion on, the page is swapped in place:
    /// the pager does not honour the setting for programmatic changes itself.
    private var stepAnimation: Animation? {
        reduceMotion ? nil : DesignSystem.Animation.easeOut
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            slide

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
                withAnimation(stepAnimation) { viewModel.goBack() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusSM)
                            // A faint chip rather than a design-system surface:
                            // it sits on the raw background and must read as a
                            // control without competing with the accent bar.
                            .fill(Color.white.opacity(0.06))
                    )
                    // Dimmed as a whole on the first step — the disabled state
                    // is the chip fading, not the glyph changing colour.
                    .opacity(viewModel.canGoBack ? 1 : 0.25)
                    // The chip stays 30pt to match the design; the *target*
                    // around it is 44pt, because this is the flow's only way
                    // back and the design's pixel size is not a hit box.
                    .frame(width: 44, height: 44)
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

    /// The slides as native pages: the finger drags the current one aside and
    /// the neighbour follows, and both ends rubber-band — nothing wraps, and a
    /// swipe past the coach slide does not finish the tour (see `go(to:)`).
    ///
    /// The selection is the view model's step, so a swipe and the Back / Next
    /// buttons are the same state change and the chrome follows either one.
    ///
    /// The geometry is read *outside* the pager, once, to give every page's
    /// scrolled content a minimum height of one viewport — what lets the welcome
    /// poster sit centred while a taller slide still scrolls. A reader inside
    /// each page can report an unresolved size on its first frame, which shows
    /// as the centred content flashing top-aligned.
    private var slide: some View {
        GeometryReader { proxy in
            TabView(selection: Binding(
                get: { viewModel.currentStep },
                set: { viewModel.go(to: $0) }
            )) {
                ForEach(viewModel.steps, id: \.self) { step in
                    OnboardingSlidePage(
                        step: step,
                        isSelected: step == viewModel.currentStep,
                        minHeight: proxy.size.height
                    )
                    .tag(step)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // `.onyxProminent` rather than `OnyxButton`, whose fixed 50pt height
            // clips a wrapped label at accessibility type sizes.
            Button {
                HapticManager.shared.light()
                withAnimation(stepAnimation) { viewModel.advance() }
            } label: {
                Text(viewModel.ctaKey.localized)
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

// MARK: - Slide page

/// One step's content, scrollable so German copy at accessibility type sizes
/// overflows downwards instead of being truncated — the same trade
/// `FounderCelebrationView` makes, with the CTA pinned below.
///
/// The pager keeps neighbouring pages mounted, so a page's scroll offset would
/// survive leaving it. Each page therefore owns its position and returns it to
/// the top the moment it stops being the selected page — while it is off
/// screen, so the reset is never seen, and so the page is entered at the top
/// going back as well as forward.
private struct OnboardingSlidePage: View {

    let step: OnboardingStep
    let isSelected: Bool
    let minHeight: CGFloat

    @State private var position = ScrollPosition(edge: .top)

    var body: some View {
        ScrollView {
            Group {
                switch step {
                case .welcome:
                    OnboardingWelcomeSlideView()
                case .routines:
                    OnboardingRoutinesSlideView()
                case .supersets:
                    OnboardingSupersetsSlideView()
                case .progressiveOverload:
                    OnboardingProgressiveOverloadSlideView()
                case .history:
                    OnboardingHistorySlideView()
                case .aiCoach:
                    OnboardingAICoachSlideView()
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.xl)
            .padding(.vertical, DesignSystem.Spacing.lg)
            .frame(
                maxWidth: .infinity,
                minHeight: minHeight,
                alignment: step.isContentCentred ? .leading : .topLeading
            )
        }
        .scrollPosition($position)
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .onChange(of: isSelected) { _, isSelected in
            if !isSelected { position.scrollTo(edge: .top) }
        }
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

#if DEBUG
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
#endif
