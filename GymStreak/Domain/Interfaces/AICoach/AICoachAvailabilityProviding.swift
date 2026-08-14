//
//  AICoachAvailabilityProviding.swift
//  GymStreak
//
//  Protocol surface for Apple Intelligence / Foundation Models availability,
//  extracted so Presentation-layer ViewModels can depend on an abstraction
//  rather than the `AICoachAvailability` singleton directly (testability / DI).
//

import Foundation

/// Mirrors the subset of `AICoachAvailability`'s public API consumed by
/// `PeriodRecapViewModel`, `ExerciseDeepDiveViewModel`, `PostWorkoutRecapViewModel`,
/// and `WorkoutAnalysisViewModel`. See `AICoachAvailability` for how `state` is
/// refreshed from `SystemLanguageModel.default.availability`.
/// `@MainActor` like the rest of the AI-coach protocol surface: the only
/// conformer (`AICoachAvailability`) is main-actor-isolated, and every consumer
/// is a `@MainActor` ViewModel or View. A nonisolated protocol here would make
/// the conformance an isolation mismatch under strict concurrency.
@MainActor
protocol AICoachAvailabilityProviding: AnyObject {

    /// Current availability state.
    var state: AICoachAvailabilityState { get }

    /// Convenience: `true` only when `state == .available`.
    var isAvailable: Bool { get }

    /// Re-queries the system and updates `state`.
    func refresh() async
}
