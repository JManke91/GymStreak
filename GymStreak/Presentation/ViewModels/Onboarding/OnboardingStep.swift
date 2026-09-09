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
/// Every run of the tour contains every case: the flow has no conditional step
/// and asks for nothing. The tour used to end on a Pro offer; it was retired
/// because a purchase request before the user has logged a single set sits in
/// front of the aha path Rule 1 protects (docs/acquisition-strategy.md §4.12).
enum OnboardingStep: Int, CaseIterable, Hashable {
    case welcome
    case routines
    case supersets
    case progressiveOverload
    case history
    case aiCoach

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
    /// Read through `OnboardingFlowViewModel.ctaKey`, never directly: the last
    /// step of the tour says "Start training" instead.
    var ctaKey: String {
        switch self {
        case .welcome: "onboarding.welcome.cta"
        default: "onboarding.cta.continue"
        }
    }

    /// The CTA of the step that ends the tour — the coach slide, whose button
    /// opens the app rather than leading to another slide.
    static let finishCTAKey = "onboarding.cta.start"
}
