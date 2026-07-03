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
@MainActor
protocol AICoachServicing: AnyObject {

    /// Streams a `PostWorkoutRecapOutput`. Returns `nil` when the surface is
    /// disabled or the device is not eligible.
    func streamPostWorkoutRecap(
        input: PostWorkoutRecapInput
    ) async throws -> LanguageModelSession.ResponseStream<PostWorkoutRecapOutput>?

    /// Streams a `PeriodRecapOutput`, falling back to a compact input under
    /// token-budget pressure. Returns `nil` when the surface is disabled or
    /// the device is not eligible.
    func streamPeriodRecap(
        buildInput: () -> PeriodRecapInput,
        buildCompactInput: () -> PeriodRecapInput
    ) async throws -> LanguageModelSession.ResponseStream<PeriodRecapOutput>?

    /// Streams an `ExerciseDeepDiveOutput`. Returns `nil` when the surface is
    /// disabled or the device is not eligible.
    func streamExerciseDeepDive(
        input: ExerciseDeepDiveInput
    ) async throws -> LanguageModelSession.ResponseStream<ExerciseDeepDiveOutput>?

    /// Streams a `WorkoutAnalysisOutput`. Returns `nil` when the surface is
    /// disabled or the device is not eligible.
    func streamWorkoutAnalysis(
        input: WorkoutAnalysisInput
    ) async throws -> LanguageModelSession.ResponseStream<WorkoutAnalysisOutput>?

    /// Warms the on-device model weights so the next generation starts faster.
    /// Safe to call multiple times — the system deduplicates concurrent warms.
    func prewarm()
}
