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
enum OnboardingStep: Int, CaseIterable, Hashable {
    case welcome
    case routines
    case supersets
    case progressiveOverload
    case history
    case aiCoach
    case offer

    /// The next step, or `nil` on the last one — which is what ends the flow.
    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    /// The previous step, or `nil` on the first one — which is what disables Back.
    var previous: OnboardingStep? {
        OnboardingStep(rawValue: rawValue - 1)
    }

    /// The localization key of this step's primary call to action.
    ///
    /// Per-step rather than one shared "Continue": the first slide invites the
    /// user in ("Let's go") and the rest move them along ("Next"). Later steps
    /// override this as they are built.
    var ctaKey: String {
        switch self {
        case .welcome: "onboarding.welcome.cta"
        default: "onboarding.cta.continue"
        }
    }
}
