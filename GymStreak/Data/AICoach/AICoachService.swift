//
//  AICoachService.swift
//  GymStreak
//
//  Central façade for all AI Coach generation requests.
//  Coordinates availability, preferences and session creation.
//
//  NOTE ON ERRORS: `LanguageModelSession.streamResponse` does not throw — a
//  generation failure surfaces when the returned stream is *iterated*, not when
//  it is created. Error classification and telemetry therefore live in the
//  consuming ViewModels' `for try await` catch blocks (they already call
//  `AICoachTelemetry.recordError`), which is where the error actually arrives.
//  A creation-time `do`/`catch` + `mapError` used to sit here; it became
//  unreachable dead code and was removed (see git history if per-`GenerationError`
//  case logging is ever wanted — it belongs at the iteration sites now).
//

import Foundation
import FoundationModels
import os

/// Central façade for all AI Coach generation calls.
///
/// Call the `streamXXX` methods to obtain a `LanguageModelSession.ResponseStream`.
/// Each method returns `nil` immediately when the corresponding surface is disabled
/// or the device is not eligible — callers do not need to check preferences separately.
///
/// **Iterating a stream (Wave 3 pattern):**
/// ```swift
/// guard let stream = try await AICoachService.shared.streamPostWorkoutRecap(input: input) else {
///     // surface disabled or unavailable — show nothing
///     return
/// }
/// for try await snapshot in stream {
///     let partial = snapshot.content   // PostWorkoutRecapOutput.PartiallyGenerated
///     let text = partial.narrative ?? ""
///     await MainActor.run { self.displayedText = text }
/// }
/// // stream exhausted — generation complete
/// ```
///
/// The last snapshot before the stream ends contains the fully-generated output.
@Observable
@MainActor
final class AICoachService: AICoachServicing {

    // MARK: - Singleton

    static let shared = AICoachService()

    // MARK: - Dependencies

    private let logger = Logger(subsystem: "app.gymstreak.aicoach", category: "AICoachService")
    private let preferences = AICoachPreferences.shared
    private let availability = AICoachAvailability.shared

    private init() {}

    // MARK: - Public API

    /// Streams a `PostWorkoutRecapOutput`.
    ///
    /// Returns `nil` when the post-workout surface is disabled or the model is unavailable.
    func streamPostWorkoutRecap(
        input: PostWorkoutRecapInput
    ) async throws -> LanguageModelSession.ResponseStream<PostWorkoutRecapOutput>? {
        guard preferences.isPostWorkoutEffectivelyEnabled, availability.isAvailable else { return nil }
        return await stream(
            instructions: PostWorkoutRecapInstructions.systemPrompt,
            promptText: input.toPromptText(),
            outputType: PostWorkoutRecapOutput.self,
            useCase: "post_workout",
            maximumResponseTokens: 200
        )
    }

    /// Streams a `PeriodRecapOutput`.
    ///
    /// `buildInput` and `buildCompactInput` are closures so they run only when needed.
    /// When running on iOS 26.4+, the token budget is checked and the compact input
    /// is used automatically when the full input would overflow the context window.
    /// On iOS 26.0–26.3 the full input is always attempted.
    ///
    /// Returns `nil` when the period recap surface is disabled or the model is unavailable.
    func streamPeriodRecap(
        buildInput: () -> PeriodRecapInput,
        buildCompactInput: () -> PeriodRecapInput
    ) async throws -> LanguageModelSession.ResponseStream<PeriodRecapOutput>? {
        guard preferences.periodRecapEnabled, preferences.isEffectivelyEnabled, availability.isAvailable else { return nil }

        let instructions = PeriodRecapInstructions.systemPrompt
        let primary = buildInput()
        let promptText = primary.toPromptText()

        // Token budget check available on iOS 26.4+. On earlier OS versions
        // we fall straight through to the full input and let the model handle it.
        if #available(iOS 26.4, *) {
            let budget = SystemLanguageModel.default.contextSize
            let instructionTokens = (try? await SystemLanguageModel.default.tokenCount(for: Instructions(instructions))) ?? 0
            let promptTokens = (try? await SystemLanguageModel.default.tokenCount(for: Prompt(promptText))) ?? 0
            let remaining = budget - instructionTokens - promptTokens
            let reservedForOutput = 700
            if remaining < reservedForOutput {
                logger.notice("period recap falling back to compact input (remaining=\(remaining))")
                let compact = buildCompactInput()
                return await stream(
                    instructions: instructions,
                    promptText: compact.toPromptText(),
                    outputType: PeriodRecapOutput.self,
                    useCase: "period_recap_compact",
                    maximumResponseTokens: 400
                )
            }
        }

        return await stream(
            instructions: instructions,
            promptText: promptText,
            outputType: PeriodRecapOutput.self,
            useCase: "period_recap",
            maximumResponseTokens: 600
        )
    }

    /// Streams an `ExerciseDeepDiveOutput`.
    ///
    /// Returns `nil` when the exercise deep-dive surface is disabled or the model is unavailable.
    func streamExerciseDeepDive(
        input: ExerciseDeepDiveInput
    ) async throws -> LanguageModelSession.ResponseStream<ExerciseDeepDiveOutput>? {
        guard preferences.exerciseDeepDiveEnabled, preferences.isEffectivelyEnabled, availability.isAvailable else { return nil }
        return await stream(
            instructions: ExerciseDeepDiveInstructions.systemPrompt,
            promptText: input.toPromptText(),
            outputType: ExerciseDeepDiveOutput.self,
            useCase: "exercise_deep_dive",
            maximumResponseTokens: 400
        )
    }

    /// Streams a `WorkoutAnalysisOutput`.
    ///
    /// Returns `nil` when the workout detail surface is disabled or the model is unavailable.
    func streamWorkoutAnalysis(
        input: WorkoutAnalysisInput
    ) async throws -> LanguageModelSession.ResponseStream<WorkoutAnalysisOutput>? {
        guard preferences.isWorkoutDetailEffectivelyEnabled, availability.isAvailable else { return nil }
        return await stream(
            instructions: WorkoutAnalysisInstructions.systemPrompt,
            promptText: input.toPromptText(),
            outputType: WorkoutAnalysisOutput.self,
            useCase: "workout_analysis",
            maximumResponseTokens: 300
        )
    }

    // MARK: - Prewarm

    /// Warms the on-device model weights so the first real generation starts faster.
    ///
    /// Call this when the user is likely to trigger a generation soon (e.g. when the
    /// AI Coach settings screen appears, or just before a workout save completes).
    /// Safe to call multiple times — the system deduplicates concurrent warms.
    func prewarm() {
        // `prewarm()` is synchronous and non-throwing in the current SDK, so the
        // previous `await` was removed. The `Task` is retained to keep behaviour
        // identical to before that change.
        //
        // ⚠️ This DEFERS, it does not OFFLOAD. Per the Swift migration guide, "a
        // newly-created task will inherit the isolation of its enclosing scope unless
        // an explicit global actor is written" — this type is `@MainActor`, so the body
        // runs on the main actor, just a turn later.
        //
        // Deliberately NOT changed to offload. SE-0461's mechanism for that would be a
        // `@concurrent` helper, but whether `LanguageModelSession.init()` /
        // `prewarm(promptPrefix:)` are safe off the main actor — and whether
        // `LanguageModelSession` is `Sendable` — is NOT DOCUMENTED by Apple (researched
        // 2026-08-13, FoundationModels doc pages unretrievable). Moving an Apple API
        // call off the main actor without its threading contract would be a guess, and
        // this is the pre-existing behaviour, not a regression. Revisit if that contract
        // gets documented. See docs/swift6-concurrency.md §9.
        Task {
            let session = LanguageModelSession()
            session.prewarm()
        }
    }

    // MARK: - Private stream helper

    private func stream<Output: Generable>(
        instructions: String,
        promptText: String,
        outputType: Output.Type,
        useCase: String,
        maximumResponseTokens: Int? = nil
    ) async -> LanguageModelSession.ResponseStream<Output> {
        let session = LanguageModelSession(instructions: Instructions(instructions))
        let start = ContinuousClock.now

        let options = maximumResponseTokens.map { GenerationOptions(maximumResponseTokens: $0) }
        let responseStream: LanguageModelSession.ResponseStream<Output>
        if let options {
            responseStream = session.streamResponse(to: promptText, generating: outputType, options: options)
        } else {
            responseStream = session.streamResponse(to: promptText, generating: outputType)
        }

        let elapsed = ContinuousClock.now - start
        let ms = Int(Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15)
        logger.debug("streamResponse created for \(useCase, privacy: .public) in \(ms)ms")
        return responseStream
    }
}
