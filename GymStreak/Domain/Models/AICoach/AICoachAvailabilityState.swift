//
//  AICoachAvailabilityState.swift
//  GymStreak
//
//  Represents the availability state of the Apple Intelligence / Foundation
//  Models subsystem needed to run the AI Coach feature. Lives in Domain
//  because it's part of `AICoachAvailabilityProviding`'s surface, consumed by
//  Presentation-layer ViewModels.
//

import Foundation

enum AICoachAvailabilityState: Equatable {
    /// The device is eligible and Apple Intelligence is ready.
    case available
    /// The hardware does not meet minimum requirements (e.g. pre-A17 Pro).
    case deviceNotEligible
    /// The hardware is eligible but the user has not enabled Apple Intelligence in Settings.
    case appleIntelligenceNotEnabled
    /// Apple Intelligence is enabled but the language model is still downloading.
    case modelNotReady
    /// Initial state before the first `refresh()` call completes.
    case unknown
}
