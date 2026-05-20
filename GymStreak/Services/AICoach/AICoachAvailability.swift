//
//  AICoachAvailability.swift
//  GymStreak
//
//  Observable wrapper for Apple Intelligence / Foundation Models availability.
//

import Foundation
import FoundationModels
import Observation

/// Represents the availability state of the Apple Intelligence / Foundation Models
/// subsystem needed to run the AI Coach feature.
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

/// Observable singleton that reports whether the AI Coach can run on this device.
///
/// Call `refresh()` on app foreground (e.g. when `ScenePhase` becomes `.active`).
/// The `state` property drives all UI branching.
@Observable
final class AICoachAvailability {

    // MARK: - Singleton

    static let shared = AICoachAvailability()
    private init() {}

    // MARK: - State

    private(set) var state: AICoachAvailabilityState = .unknown

    /// Convenience: `true` only when `state == .available`.
    var isAvailable: Bool { state == .available }

    // MARK: - Refresh

    /// Queries `SystemLanguageModel.default.availability` and updates `state`.
    ///
    /// Call this whenever `ScenePhase` transitions to `.active` so the state
    /// stays current after the user toggles Apple Intelligence in Settings.
    func refresh() async {
        let availability = SystemLanguageModel.default.availability
        let mapped: AICoachAvailabilityState
        switch availability {
        case .available:
            mapped = .available
        case .unavailable(.deviceNotEligible):
            mapped = .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            mapped = .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            mapped = .modelNotReady
        case .unavailable(_):
            // Forward-compatibility bucket for future unavailability reasons.
            mapped = .modelNotReady
        }
        await MainActor.run { self.state = mapped }
    }
}
