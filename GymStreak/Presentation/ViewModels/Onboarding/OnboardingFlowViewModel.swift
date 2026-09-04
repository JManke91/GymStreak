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
/// life in one type rather than spread across the host. The rules are simpler
/// here, because there is exactly one: **has this install seen it yet.** No
/// entitlement, no kill switch, and explicitly no test for whether the install
/// already has routines or history — everyone is toured once, updating users
/// included.
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

    init(completion: any OnboardingCompletionTracking) {
        self.completion = completion
        // Seeded here, at composition time, so the very first frame of the app
        // root already knows the cover is due — the tour has to be in front of
        // the user before they can touch the tab bar, not one render later.
        self.isPresenting = !completion.hasCompletedOnboarding
    }

    /// The 1-based number of the current step, for the counter under the CTA.
    var stepNumber: Int { currentStep.rawValue + 1 }

    /// How many steps the flow has, for the counter and the progress bar.
    var stepCount: Int { OnboardingStep.allCases.count }

    /// Whether Back does anything. `false` on the first step, where the button
    /// is shown disabled rather than removed — a control that appears on step 2
    /// would shift the whole header.
    var canGoBack: Bool { currentStep.previous != nil }

    /// Moves to the next step, or ends the flow when there is none.
    func advance() {
        guard let next = currentStep.next else {
            endFlow()
            return
        }
        currentStep = next
    }

    /// Moves back one step. A no-op on the first one.
    func goBack() {
        guard let previous = currentStep.previous else { return }
        currentStep = previous
    }

    /// Ends the flow from the "Skip" button. Records the flag exactly like
    /// finishing does: a user who skipped has decided, and re-offering the tour
    /// on the next launch would be nagging.
    func skip() {
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

    private func endFlow() {
        guard isPresenting else { return }
        isPresenting = false
        completion.recordCompleted()
    }
}
