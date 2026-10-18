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
/// and sells nothing. The tour used to end on a Pro offer; it was retired
/// because a purchase request before the user has logged a single set sits in
/// front of the aha path Rule 1 protects (docs/acquisition-strategy.md §4.12).
/// It now ends on one question instead — how the user trains — whose answer
/// only decides where the tour lands (docs/acquisition-strategy.md §4.18).
enum OnboardingStep: Int, CaseIterable, Hashable {
    case welcome
    case routines
    case supersets
    case progressiveOverload
    case history
    case aiCoach
    case trainingProfile

    /// Whether this step's content is centred in the space between the chrome
    /// or flows from the top.
    ///
    /// The welcome slide is a poster and the last step is a question; both are
    /// centred. Every feature slide leads with a fixed-height preview plate and
    /// therefore starts at the top.
    var isContentCentred: Bool {
        self == .welcome || self == .trainingProfile
    }

    /// The localization key of this step's primary call to action.
    ///
    /// Per-step rather than one shared "Continue": the first slide invites the
    /// user in ("Let's go") and the rest move them along ("Next").
    ///
    /// Read through `OnboardingFlowViewModel.ctaKey`, never directly: the last
    /// step of the tour names where it leads instead.
    var ctaKey: String {
        switch self {
        case .welcome: "onboarding.welcome.cta"
        default: "onboarding.cta.continue"
        }
    }

    /// The CTA of the step that ends the tour when the user lifts — "Start
    /// training", whose button opens the app rather than leading to another
    /// slide.
    static let finishCTAKey = "onboarding.cta.start"

    /// The CTA of the step that ends the tour when the user lifts *and* fights
    /// — it names the Fighter Strength program the tour then lands on, so the
    /// button never says "Start training" and opens a program guide instead.
    static let fightFinishCTAKey = "onboarding.cta.fight"
}
