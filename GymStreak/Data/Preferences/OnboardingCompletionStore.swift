//
//  OnboardingCompletionStore.swift
//  GymStreak
//
//  The durable half of the first-run onboarding flow: that it has been seen,
//  and what the user answered. See docs/onboarding.md.
//

import Foundation

/// Remembers that the onboarding flow was finished or skipped, so it is shown
/// once and never again on this install — and, when the user reached the last
/// step and answered it, how they train.
///
/// Plain `UserDefaults.standard`, matching `FounderCelebrationStore` — the
/// reasoning for that choice, and against iCloud KVS, is on
/// `OnboardingCompletionTracking`.
///
/// Both values are cached in memory, seeded at init, because the flow's view
/// model reads them while the app root is being composed and `UserDefaults` is
/// not observable.
@MainActor
final class OnboardingCompletionStore: OnboardingCompletionTracking {

    private(set) var hasCompletedOnboarding: Bool
    private(set) var trainingProfile: OnboardingTrainingProfile?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasCompletedOnboarding = defaults.bool(forKey: Self.completedKey)
        self.trainingProfile = defaults.string(forKey: Self.trainingProfileKey)
            .flatMap(OnboardingTrainingProfile.init(rawValue:))
    }

    func recordCompleted() {
        guard !hasCompletedOnboarding else { return }
        hasCompletedOnboarding = true
        defaults.set(true, forKey: Self.completedKey)
    }

    func recordTrainingProfile(_ profile: OnboardingTrainingProfile) {
        trainingProfile = profile
        defaults.set(profile.rawValue, forKey: Self.trainingProfileKey)
    }

    private static let completedKey = "onboarding.flowCompleted"
    private static let trainingProfileKey = "onboarding.trainingProfile"
}
