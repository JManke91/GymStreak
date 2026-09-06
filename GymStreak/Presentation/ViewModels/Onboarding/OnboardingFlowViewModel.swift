//
//  OnboardingFlowViewModel.swift
//  GymStreak
//
//  Whether the first-run onboarding flow is on screen, and which step it is on.
//  See docs/onboarding.md.
//

import Foundation
import Observation

/// The state of the first-run tour: presented or not, and where in the flow.
///
/// Same shape as `FounderCelebrationCoordinator` — an `@Observable` flag the app
/// root binds a `.fullScreenCover` to, with every rule that decides the flow's
/// life in one type rather than spread across the host. The rule that decides
/// whether the tour runs at all is exactly one: **has this install seen it yet.**
/// No entitlement, no kill switch, and explicitly no test for whether the
/// install already has routines or history — everyone is toured once, updating
/// users included.
///
/// The one thing the entitlement *does* decide is how long the tour is. Its last
/// step is the real paywall, so a Pro user, a Founder and a run with gating off
/// must not be walked to a step that will show nothing — `steps` asks the
/// presenter and the whole chrome sizes itself from the answer.
///
/// The record is spent when the flow *ends* (finished or skipped), which is a
/// user action either way, rather than when it is raised.
@Observable
@MainActor
final class OnboardingFlowViewModel {

    /// Whether the flow should be on screen. Written only by this type; the host
    /// reports a dismissal back through `flowWasDismissed()`.
    private(set) var isPresenting: Bool

    /// The step currently being shown.
    private(set) var currentStep: OnboardingStep = .welcome

    private let completion: any OnboardingCompletionTracking
    private let paywalls: any PaywallPresenting

    init(
        completion: any OnboardingCompletionTracking,
        paywalls: any PaywallPresenting
    ) {
        self.completion = completion
        self.paywalls = paywalls
        // Seeded here, at composition time, so the very first frame of the app
        // root already knows the cover is due — the tour has to be in front of
        // the user before they can touch the tab bar, not one render later.
        self.isPresenting = !completion.hasCompletedOnboarding
    }

    /// The steps this run of the tour actually has.
    ///
    /// Computed on every read rather than fixed at init, for two reasons: the
    /// entitlement resolves asynchronously after launch, so a Founder's `isPro`
    /// may well still be `false` while the welcome slide is being composed; and
    /// reading it here is what lets SwiftUI observe the answer and re-draw the
    /// progress bar if it changes mid-tour. `OnboardingStep.allCases` stays the
    /// declaration of what the tour *can* contain — this is what it contains.
    var steps: [OnboardingStep] {
        OnboardingStep.allCases.filter { $0 != .offer || isOfferStepDue }
    }

    /// Whether the last step — the Pro offer — belongs in this run at all.
    ///
    /// The presenter owns the answer: it is the same kill switch, entitlement
    /// and once-ever record every other placement is judged by, and a second
    /// copy of those rules here is how the two would drift apart.
    var isOfferStepDue: Bool {
        paywalls.isEligible(.onboarding)
    }

    /// The 1-based number of the current step, for the counter under the CTA.
    var stepNumber: Int { (steps.firstIndex(of: currentStep) ?? 0) + 1 }

    /// How many steps the flow has, for the counter and the progress bar.
    var stepCount: Int { steps.count }

    /// Whether Back does anything. `false` on the first step, where the button
    /// is shown disabled rather than removed — a control that appears on step 2
    /// would shift the whole header.
    var canGoBack: Bool { stepNumber > 1 }

    /// The localization key of the current step's call to action.
    ///
    /// The last step of the tour says so, whichever step that turns out to be:
    /// with the offer step present the coach slide leads on to it and reads
    /// "Next", and without it that same slide is the end of the tour and reads
    /// "Start training". The offer step never renders a CTA of its own — the
    /// paywall is the whole screen there.
    var ctaKey: String {
        stepNumber == stepCount ? OnboardingStep.finishCTAKey : currentStep.ctaKey
    }

    /// Moves to the next step, or ends the flow when there is none.
    func advance() {
        let steps = self.steps
        guard let index = steps.firstIndex(of: currentStep),
              index + 1 < steps.count else {
            endFlow()
            return
        }
        currentStep = steps[index + 1]
        if currentStep == .offer {
            requestOffer()
        }
    }

    /// Moves back one step. A no-op on the first one.
    func goBack() {
        let steps = self.steps
        guard let index = steps.firstIndex(of: currentStep), index > 0 else { return }
        currentStep = steps[index - 1]
    }

    /// Ends the flow from the "Skip" button. Records the flag exactly like
    /// finishing does: a user who skipped has decided, and re-offering the tour
    /// on the next launch would be nagging.
    func skip() {
        endFlow()
    }

    /// Reported by the cover when the paywall raised by the offer step has gone
    /// away — dismissed, closed after a purchase, or closed after a restore.
    ///
    /// All three end the tour: whatever the user did on the paywall, they have
    /// answered it, and the tour never comes back to ask again.
    func offerWasDismissed() {
        paywalls.dismiss()
        endFlow()
    }

    /// Reported by the host when the cover has gone away.
    ///
    /// Idempotent and guarded, so the dismissal SwiftUI writes back after
    /// `endFlow()` already lowered the flag records nothing a second time. It is
    /// also the backstop for a dismissal this type did not initiate.
    func flowWasDismissed() {
        endFlow()
    }

    /// Hands the offer step over to the app's own paywall seam.
    ///
    /// The presenter has the last word even here. `isOfferStepDue` was true when
    /// the step list was built, but the entitlement can resolve between the
    /// welcome slide and the coach slide, and Rule 3 and the "already on screen"
    /// guard are only checked inside `present(_:)`. If nothing was raised there
    /// is nothing for this step to show, so the tour ends instead of parking the
    /// user on an empty screen.
    private func requestOffer() {
        paywalls.present(.onboarding)
        if paywalls.pendingPlacement != .onboarding {
            endFlow()
        }
    }

    private func endFlow() {
        guard isPresenting else { return }
        isPresenting = false
        completion.recordCompleted()
    }
}
