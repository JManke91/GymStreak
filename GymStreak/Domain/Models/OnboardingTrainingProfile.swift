//
//  OnboardingTrainingProfile.swift
//  GymStreak
//
//  The answer to the first-run tour's last question: how does this user train?
//  See docs/onboarding.md, "Step 7 — How do you train?".
//

import Foundation

/// Which product a new user said they came for, on the tour's last step.
///
/// It is written **once**, by the CTA of that step, and it does exactly two
/// things: it decides where the tour ends (the app, or the Fighter Strength
/// program detail), and it is reported as the anonymous `trainingProfile`
/// funnel bucket (`FunnelAttributes`). **Nothing else reads it** — no gate,
/// no UI branch, no business rule — which is the same promise every other
/// funnel fact keeps (docs/funnel-instrumentation.md §2).
///
/// The raw value is the *stored* form (`OnboardingCompletionStore`), not the
/// wire form: the dashboard vocabulary is spelled only in `FunnelAttributes`,
/// so renaming a case here can never silently rename a chart filter.
enum OnboardingTrainingProfile: String, CaseIterable, Hashable, Sendable {

    /// Strength training only — today's product, unchanged.
    case lift

    /// Strength training around a combat sport: the Fighter Strength program
    /// and fight conditioning.
    case fight
}
