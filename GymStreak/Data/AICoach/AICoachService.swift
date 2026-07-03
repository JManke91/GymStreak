//
//  AICoachService.swift
//  GymStreak
//
//  Central façade for all AI Coach generation requests.
//  Coordinates availability, preferences, session creation, and error mapping.
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
        return try await stream(
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
                return try await stream(
                    instructions: instructions,
                    promptText: compact.toPromptText(),
                    outputType: PeriodRecapOutput.self,
                    useCase: "period_recap_compact",
                    maximumResponseTokens: 400
                )
            }
        }

        return try await stream(
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
        return try await stream(
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
        return try await stream(
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
        Task {
            let session = LanguageModelSession()
            await session.prewarm()
        }
    }

    // MARK: - Private stream helper

    private func stream<Output: Generable>(
        instructions: String,
        promptText: String,
        outputType: Output.Type,
        useCase: String,
        maximumResponseTokens: Int? = nil
    ) async throws -> LanguageModelSession.ResponseStream<Output> {
        let session = LanguageModelSession(instructions: Instructions(instructions))
        let start = ContinuousClock.now

        do {
            let options = maximumResponseTokens.map { GenerationOptions(maximumResponseTokens: $0) }
            let responseStream: LanguageModelSession.ResponseStream<Output>
            if let options {
                responseStream = try session.streamResponse(to: promptText, generating: outputType, options: options)
            } else {
                responseStream = try session.streamResponse(to: promptText, generating: outputType)
            }
            let elapsed = ContinuousClock.now - start
            let ms = Int(Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15)
            logger.debug("streamResponse created for \(useCase, privacy: .public) in \(ms)ms")
            return responseStream
        } catch {
            let elapsed = ContinuousClock.now - start
            let ms = Int(Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15)
            logger.error("streamResponse threw for \(useCase, privacy: .public) after \(ms)ms")
            AICoachTelemetry.recordError(useCase: useCase, errorTypeName: String(describing: type(of: error)))
            throw mapError(error, useCase: useCase)
        }
    }

    // MARK: - Error mapping

    private func mapError(_ error: Error, useCase: String) -> Error {
        guard let gen = error as? LanguageModelSession.GenerationError else { return error }
        switch gen {
        case .guardrailViolation(_):
            logger.warning("guardrail violation in \(useCase, privacy: .public)")
        case .exceededContextWindowSize(_):
            logger.error("context window exceeded in \(useCase, privacy: .public) — input may be too large")
        case .assetsUnavailable(_):
            logger.notice("assets unavailable in \(useCase, privacy: .public)")
        case .rateLimited(_):
            logger.notice("rate limited in \(useCase, privacy: .public)")
        case .unsupportedLanguageOrLocale(_):
            logger.error("unsupported locale in \(useCase, privacy: .public)")
        case .decodingFailure(_):
            logger.error("decoding failure in \(useCase, privacy: .public)")
        case .unsupportedGuide(_):
            logger.error("unsupported @Guide in \(useCase, privacy: .public)")
        @unknown default:
            logger.error("unknown GenerationError in \(useCase, privacy: .public)")
        }
        return error
    }
}
