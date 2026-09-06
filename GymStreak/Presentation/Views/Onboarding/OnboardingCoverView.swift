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

    /// The paywall seam, for the offer step. Passed in rather than reached for,
    /// and read here only to render what the view model already raised.
    let paywalls: any PaywallPresenting

    /// Handed to `ProPaywallView` so a restore made from the tour is judged by
    /// the same rule every gate is judged by. Read nowhere else here.
    let entitlements: any ProEntitlementProviding

    var body: some View {
        Group {
            if viewModel.currentStep == .offer {
                // The offer step draws no chrome. The paywall below owns the
                // screen, and a progress bar with a dead CTA under a sheet the
                // user cannot dismiss into anything is worse than a plain
                // background for the length of one presentation animation.
                Color.clear
            } else {
                VStack(spacing: 0) {
                    header

                    slide

                    footer
                }
            }
        }
        .background(DesignSystem.Colors.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        // The tour hosts its own paywall, exactly as the coach-chat cover does
        // and for exactly the same reason: **a sheet raised while a full-screen
        // cover is up never reaches the screen** (docs/onboarding.md, "Cover
        // ordering"). The alternative — dismissing this cover first and letting
        // the app root's sheet take the request — puts the dismissal and the
        // presentation in one SwiftUI transaction, which is the case SwiftUI is
        // documented to drop. That would silently swallow the offer, and the
        // placement would then surface later, out of nowhere, on whatever screen
        // the user had reached.
        //
        // Filtered to `.onboarding`: any other placement that somehow fires
        // while the tour is up belongs to the app behind it, stays pending, and
        // is picked up by the root host once this cover goes away.
        .sheet(item: offerBinding) { placement in
            ProPaywallView(
                placement: placement,
                entitlements: entitlements,
                onPaywallShown: { paywalls.didPresent(placement) }
            )
            .onAppear { paywalls.sheetDidAppear() }
        }
    }

    /// The offer step's paywall, with its dismissal ending the tour.
    ///
    /// Only a dismissal is written back — the view model raises the placement,
    /// nothing here does — and every way out of the paywall arrives here:
    /// the close button, a completed purchase and a successful restore all end
    /// in `ProPaywallView` calling `dismiss()`.
    private var offerBinding: Binding<PaywallPlacement?> {
        Binding(
            get: { paywalls.pendingPlacement == .onboarding ? .onboarding : nil },
            set: { if $0 == nil { viewModel.offerWasDismissed() } }
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            Button {
                HapticManager.shared.light()
                withAnimation(DesignSystem.Animation.easeOut) { viewModel.goBack() }
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

    /// The step's own content, scrollable so German copy at accessibility type
    /// sizes overflows downwards instead of being truncated — the same trade
    /// `FounderCelebrationView` makes, with the CTA pinned below.
    private var slide: some View {
        // The geometry is read to give the scrolled content a *minimum* height
        // of one viewport. That is what lets a short slide sit centred — the
        // welcome poster does — while a slide that outgrows the screen still
        // scrolls normally. Reading the size costs nothing here: it is one
        // container, not a per-row measurement.
        GeometryReader { proxy in
            ScrollView {
                Group {
                    switch viewModel.currentStep {
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
                    case .offer:
                        // Unreachable: `body` swaps the whole chrome out for the
                        // offer step, which is the paywall and nothing else.
                        Color.clear.frame(height: 1)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.xl)
                .padding(.vertical, DesignSystem.Spacing.lg)
                .frame(
                    maxWidth: .infinity,
                    minHeight: proxy.size.height,
                    alignment: viewModel.currentStep.isContentCentred ? .leading : .topLeading
                )
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            // A fresh identity per step, which is what puts the new slide at the
            // top of its scroll: the offset belongs to the `ScrollView`, so
            // re-identifying it is the reset — going back as well as forward.
            //
            // On the `ScrollView` and *not* on the `GeometryReader` around it:
            // re-identifying the reader too would rebuild it every step, leaving
            // `proxy.size` unresolved for one layout pass and flashing the
            // centred content top-aligned before it settles.
            .id(viewModel.currentStep)
        }
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
/// Free, so the preview shows the tour at its full seven steps. Declared at file
/// scope because `ProEntitlementProviding` is an `AnyObject` protocol.
@MainActor
private final class PreviewFreeEntitlements: ProEntitlementProviding {
    let state: ProEntitlementState = .free
    var isPro: Bool { false }
    func refresh() async {}
    func restorePurchases() async -> ProRestoreOutcome { .nothingFound }
}

/// Eligible but inert: the preview is about the chrome and the slides, and a
/// preview that reached the RevenueCat SDK would render its loading spinner.
@MainActor
private final class PreviewEligiblePaywalls: PaywallPresenting {
    var pendingPlacement: PaywallPlacement?
    func present(_ placement: PaywallPlacement) {}
    func isEligible(_ placement: PaywallPlacement) -> Bool { true }
    func sheetDidAppear() {}
    func didPresent(_ placement: PaywallPlacement) {}
    func dismiss() {}
    func hasPresented(_ placement: PaywallPlacement) -> Bool { false }
}

#Preview {
    OnboardingCoverView(
        viewModel: OnboardingFlowViewModel(
            // A throwaway suite, so tapping through the preview cannot record the
            // real "already onboarded" flag on the simulator.
            completion: OnboardingCompletionStore(
                defaults: UserDefaults(suiteName: "preview.onboarding") ?? .standard
            ),
            paywalls: PreviewEligiblePaywalls()
        ),
        paywalls: PreviewEligiblePaywalls(),
        entitlements: PreviewFreeEntitlements()
    )
}
#endif
