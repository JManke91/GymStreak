//
//  AICoachAvailability.swift
//  GymStreak
//
//  Observable wrapper for Apple Intelligence / Foundation Models availability.
//

import Foundation
import FoundationModels
import Observation

/// Observable singleton that reports whether the AI Coach can run on this device.
///
/// Call `refresh()` on app foreground (e.g. when `ScenePhase` becomes `.active`).
/// The `state` property drives all UI branching.
///
/// `AICoachAvailabilityState` lives in `Domain/Models/AICoach/AICoachAvailabilityState.swift`
/// so it can be shared with the `AICoachAvailabilityProviding` Domain protocol
/// this class conforms to.
@Observable
final class AICoachAvailability: AICoachAvailabilityProviding {

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
