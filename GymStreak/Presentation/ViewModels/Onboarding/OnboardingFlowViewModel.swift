//
//  OnboardingFlowViewModel.swift
//  GymStreak
//
//  Whether the first-run onboarding flow is on screen, which step it is on, and
//  how its one question was answered. See docs/onboarding.md.
//

import Foundation
import Observation

/// The state of the first-run tour: presented or not, where in the flow, and
/// which training profile is selected on its last step.
///
/// Same shape as `FounderCelebrationCoordinator` — an `@Observable` flag the app
/// root binds a `.fullScreenCover` to, with every rule that decides the flow's
/// life in one type rather than spread across the host. The rule that decides
/// whether the tour runs at all is exactly one: **has this install seen it yet.**
/// No entitlement, no kill switch, and explicitly no test for whether the
/// install already has routines or history — everyone is toured once, updating
/// users included.
///
/// The tour sells nothing. It has no paywall seam and no conditional step:
/// the first purchase request in the app's life belongs after the user has
/// logged something (docs/acquisition-strategy.md §4.12), so it falls to
/// `.firstRoutineCreated` and `.valueMoment` instead. Its last step asks one
/// question — "How do you train?" — whose answer decides only where the tour
/// ends: in the app, or on the Fighter Strength program detail.
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

    /// The answer selected on the last step. `.lift` by default — today's
    /// product — so the CTA always leads somewhere; it is recorded only when
    /// that step's CTA is tapped (`finish()`), never by selecting.
    private(set) var selectedTrainingProfile: OnboardingTrainingProfile = .lift

    private let completion: any OnboardingCompletionTracking

    /// Optional for the same reason `WorkoutViewModel`'s coordinators are: a
    /// unit-test instance has no purchase backend to report to.
    private let funnelAttributes: (any FunnelAttributeTracking)?

    /// Where "I lift and fight" lands: the Routines tab opens the Fighter
    /// Strength program detail through this seam once the cover is gone.
    /// Optional like the funnel: a unit-test instance may have no tab to send
    /// the request to.
    private let programDetails: (any ProgramDetailRequesting)?

    init(
        completion: any OnboardingCompletionTracking,
        funnelAttributes: (any FunnelAttributeTracking)? = nil,
        programDetails: (any ProgramDetailRequesting)? = nil
    ) {
        self.completion = completion
        self.funnelAttributes = funnelAttributes
        self.programDetails = programDetails
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
    /// The last step says where it leads: "Start training" for a lifter, and
    /// the Fighter Strength program by name for a fighter — a button that said
    /// "Start training" and then opened a program guide would be a surprise.
    var ctaKey: String {
        guard stepNumber == stepCount else { return currentStep.ctaKey }
        return selectedTrainingProfile == .fight
            ? OnboardingStep.fightFinishCTAKey
            : OnboardingStep.finishCTAKey
    }

    /// Moves to the next step, or ends the flow when there is none.
    func advance() {
        let steps = self.steps
        guard let index = steps.firstIndex(of: currentStep),
              index + 1 < steps.count else {
            finish()
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

    /// Moves straight to `step` — the path a swipe between slides takes.
    ///
    /// Unlike `advance()`, this never ends the flow: a swipe past the last slide
    /// just rubber-bands, so finishing (which spends the once-ever record) stays
    /// an explicit tap on the CTA. A step outside `steps` is ignored.
    func go(to step: OnboardingStep) {
        guard steps.contains(step) else { return }
        currentStep = step
    }

    /// Changes the answer on the last step. Selecting commits nothing — the
    /// user can change their mind until the CTA, and a tour skipped from here
    /// records no answer at all.
    func selectTrainingProfile(_ profile: OnboardingTrainingProfile) {
        selectedTrainingProfile = profile
    }

    /// Ends the flow from the "Skip" button. Records the flag exactly like
    /// finishing does: a user who skipped has decided, and re-offering the tour
    /// on the next launch would be nagging. The question stays unanswered.
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

    /// The CTA of the last step — the one path that records an answer.
    ///
    /// Only reachable from the last step (`advance()` ends the flow nowhere
    /// else), so reaching here means the user saw the question. The answer is
    /// written **before** the flow ends, because `endFlow()` reports the funnel
    /// and the report reads the record back. A fighter's landing is requested
    /// before the cover comes down as well: the Routines tab pushes the detail
    /// underneath it, so the tour ends *on* the program rather than arriving
    /// at it a beat later.
    private func finish() {
        guard isPresenting else { return }
        completion.recordTrainingProfile(selectedTrainingProfile)
        if selectedTrainingProfile == .fight {
            programDetails?.requestProgramDetail(RoutineProgramCatalog.fighterStrength.id)
        }
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
