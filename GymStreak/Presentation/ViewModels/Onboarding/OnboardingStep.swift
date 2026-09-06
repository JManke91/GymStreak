//
//  OnboardingStep.swift
//  GymStreak
//
//  The steps of the first-run onboarding flow, in the order they are shown.
//  See docs/onboarding.md.
//

import Foundation

/// One step of the onboarding flow.
///
/// The whole flow is declared here rather than assembled by the views, so the
/// progress bar, the step counter and the navigation all derive their length
/// from one list: adding a slide is adding a case, not touching the chrome.
/// The `Int` raw values are the order and nothing else — they are never
/// persisted, so they are free to change.
///
/// This is what the tour *can* contain. What a given run actually contains is
/// `OnboardingFlowViewModel.steps`, which drops `.offer` for a user the paywall
/// seam would show nothing to — a Pro user, a Founder, a run with gating off,
/// or one where the placement has already fired.
enum OnboardingStep: Int, CaseIterable, Hashable {
    case welcome
    case routines
    case supersets
    case progressiveOverload
    case history
    case aiCoach
    case offer

    /// Whether this step's content is centred in the space between the chrome
    /// or flows from the top.
    ///
    /// The welcome slide is a poster and is centred; every feature slide leads
    /// with a fixed-height preview plate and therefore starts at the top.
    var isContentCentred: Bool {
        self == .welcome
    }

    /// The localization key of this step's primary call to action.
    ///
    /// Per-step rather than one shared "Continue": the first slide invites the
    /// user in ("Let's go") and the rest move them along ("Next").
    ///
    /// Read through `OnboardingFlowViewModel.ctaKey`, never directly: the *last*
    /// step of a run says "Start training" instead, and which step that is
    /// depends on whether the offer step is due.
    var ctaKey: String {
        switch self {
        case .welcome: "onboarding.welcome.cta"
        default: "onboarding.cta.continue"
        }
    }

    /// The CTA of whichever step ends the tour — the coach slide when the offer
    /// step is not due, and nothing at all when it is, because the offer step
    /// hands the whole screen to the paywall and draws no chrome of its own.
    static let finishCTAKey = "onboarding.cta.start"
}
