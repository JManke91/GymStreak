//
//  AICoachServicing.swift
//  GymStreak
//
//  Protocol surface for the AI Coach LLM generation façade, extracted so
//  Presentation-layer ViewModels can depend on an abstraction rather than
//  the `AICoachService` singleton directly (testability / DI).
//

import Foundation
import FoundationModels

/// Generation surface used by the AI Coach ViewModels.
///
/// Mirrors the subset of `AICoachService`'s public API consumed by
/// `PeriodRecapViewModel`, `ExerciseDeepDiveViewModel`, `PostWorkoutRecapViewModel`,
/// and `WorkoutAnalysisViewModel`. See `AICoachService` for full documentation
/// of streaming semantics and error mapping.
///
/// **`weightUnit` travels beside the input rather than inside it.** The inputs are
/// `@Generable`, so every stored property must itself be `Generable` — and making
/// `WeightUnit` so would drag `FoundationModels` into a Domain type that the watch
/// target copies verbatim. Keeping it a parameter also puts the unit and the
/// instructions in one call: the prompt tells the model which unit it is reading, and
/// the figures are converted into that same one. See docs/weight-unit-preference.md §13.
@MainActor
protocol AICoachServicing: AnyObject {

    /// Streams a `PostWorkoutRecapOutput`. Returns `nil` when the surface is
    /// disabled or the device is not eligible.
    func streamPostWorkoutRecap(
        input: PostWorkoutRecapInput,
        weightUnit: WeightUnit
    ) async throws -> LanguageModelSession.ResponseStream<PostWorkoutRecapOutput>?

    /// Streams a `PeriodRecapOutput`, falling back to a compact input under
    /// token-budget pressure. Returns `nil` when the surface is disabled or
    /// the device is not eligible.
    func streamPeriodRecap(
        buildInput: () -> PeriodRecapInput,
        buildCompactInput: () -> PeriodRecapInput,
        weightUnit: WeightUnit
    ) async throws -> LanguageModelSession.ResponseStream<PeriodRecapOutput>?

    /// Streams an `ExerciseDeepDiveOutput`. Returns `nil` when the surface is
    /// disabled or the device is not eligible.
    func streamExerciseDeepDive(
        input: ExerciseDeepDiveInput,
        weightUnit: WeightUnit
    ) async throws -> LanguageModelSession.ResponseStream<ExerciseDeepDiveOutput>?

    /// Streams a `WorkoutAnalysisOutput`. Returns `nil` when the surface is
    /// disabled or the device is not eligible.
    func streamWorkoutAnalysis(
        input: WorkoutAnalysisInput,
        weightUnit: WeightUnit
    ) async throws -> LanguageModelSession.ResponseStream<WorkoutAnalysisOutput>?

    /// Warms the on-device model weights so the next generation starts faster.
    /// Safe to call multiple times — the system deduplicates concurrent warms.
    func prewarm()
}
