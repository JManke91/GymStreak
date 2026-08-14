//
//  AICoachPreferencesProviding.swift
//  GymStreak
//
//  Protocol surface for AI Coach user preferences, extracted so Presentation-layer
//  ViewModels can depend on an abstraction rather than the `AICoachPreferences`
//  singleton directly (testability / DI).
//

import Foundation

/// Effective-state preference surface used by the AI Coach ViewModels.
///
/// Mirrors the subset of `AICoachPreferences`'s public API consumed by
/// `PeriodRecapViewModel`, `ExerciseDeepDiveViewModel`, `PostWorkoutRecapViewModel`,
/// and `WorkoutAnalysisViewModel`. See `AICoachPreferences` for the full
/// persisted-settings surface and opt-in logic.
/// `@MainActor` like the rest of the AI-coach protocol surface: the only
/// conformer (`AICoachPreferences`) is main-actor-isolated, and every consumer
/// is a `@MainActor` ViewModel or View. A nonisolated protocol here would make
/// the conformance an isolation mismatch under strict concurrency.
@MainActor
protocol AICoachPreferencesProviding: AnyObject {

    /// Monthly period recap is active.
    var isPeriodRecapEffectivelyEnabled: Bool { get }

    /// Proactive monthly prompt is active.
    var isProactiveMonthlyEffectivelyEnabled: Bool { get }

    /// Last monthly period for which the proactive prompt was consumed.
    var lastProactivePromptShownForPeriodId: String? { get set }

    /// Exercise deep-dive surface is active.
    var isExerciseDeepDiveEffectivelyEnabled: Bool { get }

    /// Post-workout recap is active.
    var isPostWorkoutEffectivelyEnabled: Bool { get }

    /// Workout detail analysis surface is active.
    var isWorkoutDetailEffectivelyEnabled: Bool { get }
}
