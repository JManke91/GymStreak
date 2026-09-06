//
//  OnboardingOfferStepTests.swift
//  GymStreakTests
//
//  Step 7 of the first-run tour: the Pro offer (docs/onboarding.md,
//  "Step 7 — the offer"). Split from `OnboardingFlowTests`, which is about the
//  tour's own life — when it appears, when it is spent, how it navigates.
//
//  What carries the ticket is that the step is *conditional*: it exists only
//  when the paywall seam would actually show something, the tour resizes itself
//  around that answer, and every way out of the paywall ends the tour for good.
//
//  These run against the real `PaywallPresenter` over a throwaway defaults
//  suite, because the step's presence *is* its eligibility answer — a double
//  would assert that away.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
@MainActor
struct OnboardingOfferStepTests {

    @Test("A free user's tour ends on the paywall step")
    func offerStepIsDueForAFreeUser() {
        let viewModel = makeViewModel()

        #expect(viewModel.isOfferStepDue)
        #expect(viewModel.stepCount == 7)
        #expect(viewModel.steps.last == .offer)
    }

    @Test("Reaching the last step raises the onboarding placement")
    func reachingTheLastStepRaisesThePaywall() {
        let paywalls = makePresenter()
        let viewModel = makeViewModel(paywalls: paywalls)

        for _ in 0..<(viewModel.stepCount - 1) {
            viewModel.advance()
        }

        #expect(viewModel.currentStep == .offer)
        #expect(paywalls.pendingPlacement == .onboarding)
        // The tour is still up: the paywall is hosted inside its cover.
        #expect(viewModel.isPresenting)
    }

    @Test("Dismissing the paywall clears it and ends the tour for good")
    func dismissingTheOfferEndsTheTour() {
        let defaults = makeDefaults()
        let paywalls = makePresenter()
        let viewModel = makeViewModel(defaults: defaults, paywalls: paywalls)

        for _ in 0..<(viewModel.stepCount - 1) {
            viewModel.advance()
        }
        viewModel.offerWasDismissed()

        #expect(!viewModel.isPresenting)
        #expect(paywalls.pendingPlacement == nil)
        // Whatever the user did on it — dismissed, bought, restored — the tour
        // is over, and the next launch goes straight to the tabs.
        #expect(!makeViewModel(defaults: defaults).isPresenting)
    }

    @Test("Skipping from the coach slide never raises the paywall")
    func skippingNeverRaisesTheOffer() {
        let paywalls = makePresenter()
        let viewModel = makeViewModel(paywalls: paywalls)

        for _ in 0..<(viewModel.stepCount - 2) {
            viewModel.advance()
        }
        #expect(viewModel.currentStep == .aiCoach)

        viewModel.skip()

        #expect(paywalls.pendingPlacement == nil)
        #expect(!viewModel.isPresenting)
    }

    @Test("A Pro user, a Founder and a run with gating off never see the step")
    func offerStepIsAbsentWhenThePaywallWouldShowNothing() {
        for presenter in [
            makePresenter(entitlements: .subscription),
            makePresenter(entitlements: .founder),
            makePresenter(isGatingEnabled: false)
        ] {
            let viewModel = makeViewModel(paywalls: presenter)

            #expect(!viewModel.isOfferStepDue)
            #expect(viewModel.stepCount == 6)
            #expect(!viewModel.steps.contains(.offer))
            // No dead final segment: the coach slide is the last step, and its
            // CTA says so.
            #expect(viewModel.steps.last == .aiCoach)
        }
    }

    @Test("Without the offer step the coach slide finishes the tour directly")
    func coachSlideFinishesTheTourWhenTheOfferIsAbsent() {
        let defaults = makeDefaults()
        let paywalls = makePresenter(entitlements: .founder)
        let viewModel = makeViewModel(defaults: defaults, paywalls: paywalls)

        for _ in 0..<(viewModel.stepCount - 1) {
            viewModel.advance()
        }

        #expect(viewModel.currentStep == .aiCoach)
        #expect(viewModel.ctaKey == OnboardingStep.finishCTAKey)

        viewModel.advance()

        #expect(!viewModel.isPresenting)
        #expect(paywalls.pendingPlacement == nil)
        #expect(!makeViewModel(defaults: defaults).isPresenting)
    }

    @Test("The offer fires once ever, even if the tour is somehow re-entered")
    func theOfferFiresOnlyOnce() {
        // One presenter and one defaults suite across two runs of the tour: the
        // second run is what a debug reset of the completion flag produces, and
        // the placement must already be spent.
        let paywallDefaults = makeDefaults()
        let paywalls = makePresenter(defaults: paywallDefaults)
        let first = makeViewModel(paywalls: paywalls)

        for _ in 0..<(first.stepCount - 1) {
            first.advance()
        }
        // What the host reports once the paywall's offer is on screen.
        paywalls.sheetDidAppear()
        paywalls.didPresent(.onboarding)
        first.offerWasDismissed()

        let second = makeViewModel(paywalls: paywalls)

        #expect(!second.isOfferStepDue)
        #expect(second.stepCount == 6)

        for _ in 0..<second.stepCount {
            second.advance()
        }

        #expect(paywalls.pendingPlacement == nil)
        #expect(!second.isPresenting)
    }

    @Test("A step list that loses the offer mid-tour still ends the tour")
    func offerLostBetweenSlidesEndsTheTour() {
        // The entitlement resolves asynchronously, so a Founder can be `free` on
        // the welcome slide and Pro by the coach slide. The step list shortens
        // under the user; advancing off its end must end the tour rather than
        // park them on a step whose paywall will refuse to appear.
        let entitlements = StubProEntitlements(state: .free)
        let paywalls = PaywallPresenter(
            entitlements: entitlements,
            activeWorkout: ActiveWorkoutRegistry(),
            isGatingEnabled: true,
            defaults: makeDefaults()
        )
        let viewModel = makeViewModel(paywalls: paywalls)

        for _ in 0..<(viewModel.stepCount - 2) {
            viewModel.advance()
        }
        #expect(viewModel.currentStep == .aiCoach)

        entitlements.state = .founder
        viewModel.advance()

        #expect(!viewModel.isPresenting)
        #expect(paywalls.pendingPlacement == nil)
    }

    @Test("The offer step's placement and headline are localized in both roles")
    func offerPlacementIsLocalized() {
        #expect(PaywallPlacement.onboarding.identifier == "onboarding")
        #expect(PaywallPlacement.onboarding.isOneShot)
        #expect(PaywallPlacement.onboarding.headlineKey.localized
            != PaywallPlacement.onboarding.headlineKey)
    }

    // MARK: - Harness

    private func makeViewModel(
        defaults: UserDefaults? = nil,
        paywalls: (any PaywallPresenting)? = nil
    ) -> OnboardingFlowViewModel {
        OnboardingFlowViewModel(
            completion: OnboardingCompletionStore(defaults: defaults ?? makeDefaults()),
            paywalls: paywalls ?? makePresenter()
        )
    }

    /// Gating is on, unlike a default `PaywallPresenter`, so the flow under test
    /// is the shipping one rather than the kill-switched one.
    private func makePresenter(
        entitlements: ProEntitlementState = .free,
        isGatingEnabled: Bool = true,
        defaults: UserDefaults? = nil
    ) -> PaywallPresenter {
        PaywallPresenter(
            entitlements: StubProEntitlements(state: entitlements),
            activeWorkout: ActiveWorkoutRegistry(),
            isGatingEnabled: isGatingEnabled,
            defaults: defaults ?? makeDefaults()
        )
    }

    /// A throwaway suite per test: the real stores write `UserDefaults.standard`,
    /// which the developer's simulator shares.
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "OnboardingOfferStepTests.\(UUID().uuidString)")!
    }
}
