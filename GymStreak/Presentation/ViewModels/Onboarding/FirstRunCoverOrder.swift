//
//  FirstRunCoverOrder.swift
//  GymStreak
//
//  Which of the three first-launch full-screen covers is on screen.
//  See docs/onboarding.md, "Cover ordering".
//

import Foundation

/// A screen that can claim the whole window on a first launch, declared in the
/// order the user must meet them: the tour teaches what the app is, the Founder
/// thank-you reassures whoever earned it, and the coach opt-in asks for a
/// decision. Reversing any pair asks something of a user who does not yet know
/// what they are being asked about.
enum FirstRunCover: CaseIterable {
    case onboarding
    case founderCelebration
    case coachOptIn
}

/// The one rule that decides which first-run cover the app root hosts.
///
/// It exists as a type rather than as three boolean expressions at the host for
/// two reasons. **Exactly one cover at a time** is then structurally true — one
/// `FirstRunCover?` cannot name two screens — rather than an invariant that
/// holds only as long as three hand-written suppression clauses agree with each
/// other. And the ordering becomes testable without a running SwiftUI
/// hierarchy: `FirstRunCoverOrderTests` walks every combination of the three
/// conditions, which is what the host's inline `&& !isOnboarding` chain could
/// never be asked.
///
/// **Suppression never drops anything.** The result is recomputed from live
/// conditions on every render, and none of the three spends its record by
/// failing to present: `FounderCelebrationCoordinator` writes only on dismissal,
/// the tour's flag is written only when it ends, and the opt-in re-reads
/// `AICoachPreferences`/`AICoachAvailability` every time. So a cover whose
/// condition turns true *while another is up* — the coach opt-in in particular,
/// whose Apple Intelligence availability resolves asynchronously after launch —
/// simply becomes the topmost one once the cover above it goes away.
enum FirstRunCoverOrder {

    /// The cover that should be presented right now, or `nil` for the tab bar.
    ///
    /// - Parameters:
    ///   - isOnboarding: `OnboardingFlowViewModel.isPresenting`.
    ///   - isCelebratingFounder: `FounderCelebrationCoordinator.isPresenting`.
    ///   - shouldShowCoachOptIn: Apple Intelligence is available *and* the user
    ///     has neither completed nor permanently dismissed the opt-in.
    static func topmost(
        isOnboarding: Bool,
        isCelebratingFounder: Bool,
        shouldShowCoachOptIn: Bool
    ) -> FirstRunCover? {
        if isOnboarding { return .onboarding }
        if isCelebratingFounder { return .founderCelebration }
        if shouldShowCoachOptIn { return .coachOptIn }
        return nil
    }
}
