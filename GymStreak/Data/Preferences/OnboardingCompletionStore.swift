//
//  OnboardingCompletionStore.swift
//  GymStreak
//
//  The durable half of the first-run onboarding flow: that it has been seen.
//  See docs/onboarding.md.
//

import Foundation

/// Remembers that the onboarding flow was finished or skipped, so it is shown
/// once and never again on this install.
///
/// Plain `UserDefaults.standard`, matching `FounderCelebrationStore` — the
/// reasoning for that choice, and against iCloud KVS, is on
/// `OnboardingCompletionTracking`.
///
/// The flag is cached in memory, seeded at init, because the flow's view model
/// reads it while the app root is being composed and `UserDefaults` is not
/// observable.
@MainActor
final class OnboardingCompletionStore: OnboardingCompletionTracking {

    private(set) var hasCompletedOnboarding: Bool
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasCompletedOnboarding = defaults.bool(forKey: Self.completedKey)
    }

    func recordCompleted() {
        guard !hasCompletedOnboarding else { return }
        hasCompletedOnboarding = true
        defaults.set(true, forKey: Self.completedKey)
    }

    private static let completedKey = "onboarding.flowCompleted"
}
