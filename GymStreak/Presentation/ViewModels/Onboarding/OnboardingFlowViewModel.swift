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
/// The tour asks for nothing. It has no paywall seam and no conditional step:
/// the first purchase request in the app's life belongs after the user has
/// logged something (docs/acquisition-strategy.md §4.12), so it falls to
/// `.firstRoutineCreated` and `.valueMoment` instead.
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

    /// Optional for the same reason `WorkoutViewModel`'s coordinators are: a
    /// unit-test instance has no purchase backend to report to.
    private let funnelAttributes: (any FunnelAttributeTracking)?

    init(
        completion: any OnboardingCompletionTracking,
        funnelAttributes: (any FunnelAttributeTracking)? = nil
    ) {
        self.completion = completion
        self.funnelAttributes = funnelAttributes
        // Seeded here, at composition time, so the very first frame of the app
        // root already knows the cover is due — the tour has to be in front of
        // the user before they can touch the tab bar, not one render later.
        self.isPresenting = !completion.hasCompletedOnboarding
    }

    /// The steps this run of the tour has — all of them, every time.
    ///
    /// Kept as the one list the chrome sizes itself from, so a slide added to or
    /// cut from `OnboardingStep` moves the progress bar and the counter with it.
    var steps: [OnboardingStep] { OnboardingStep.allCases }

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
    /// The last step says so: the coach slide ends the tour and reads "Start
    /// training" rather than "Next".
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
        // **After** `recordCompleted()`, and in this session rather than on the
        // next cold launch: the reporter reads the record back, and a user who
        // finishes the tour and never returns must not be counted as a bail-out
        // (docs/funnel-instrumentation.md). Detached into a `Task` because
        // reporting is analytics — nothing about the tour ending may wait on it.
        Task { [funnelAttributes] in await funnelAttributes?.reportCurrentState() }
    }
}
