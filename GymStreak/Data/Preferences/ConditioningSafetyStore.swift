//
//  ConditioningSafetyStore.swift
//  GymStreak
//
//  Device-local like `OnboardingCompletionStore`: seeing the safety screen once
//  more on a new install is the cheaper mistake than never seeing it.
//

import Foundation

@MainActor
final class ConditioningSafetyStore: ConditioningSafetyAcknowledging {

    private(set) var hasAcknowledgedSafety: Bool
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasAcknowledgedSafety = defaults.bool(forKey: Self.acknowledgedKey)
    }

    func recordSafetyAcknowledged() {
        guard !hasAcknowledgedSafety else { return }
        hasAcknowledgedSafety = true
        defaults.set(true, forKey: Self.acknowledgedKey)
    }

    private static let acknowledgedKey = "conditioning.safetyAcknowledged"
}
