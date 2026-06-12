//
//  WorkoutAnalysisViewModel.swift
//  GymStreak
//
//  Orchestrates AI Coach workout detail analysis generation.
//  Handles availability checks, preferences gating, caching,
//  streaming, and graceful degradation — all AI logic stays
//  out of the view layer.
//

import Foundation
import SwiftData
import FoundationModels
import os

/// Orchestrates workout analysis generation for `WorkoutDetailView`.
///
/// Lifecycle:
/// 1. `checkCache(workout:)` is called on `.task` in `WorkoutDetailView`.
///    If a cached result exists, the state transitions directly to `.success`.
/// 2. If no cache hit, the view renders `CoachWorkoutAnalysisButton`. Tapping it
///    calls `generate(workout:locale:modelContext:)`.
/// 3. `regenerate(...)` bypasses the cache and forces a fresh generation.
@Observable
@MainActor
final class WorkoutAnalysisViewModel {

    // MARK: - State

    enum AnalysisState: Equatable {
        /// Initial — nothing shown yet.
        case idle
        /// Model is streaming; associated text grows incrementally.
        case streaming(text: String)
        /// Generation complete; text contains the full narrative.
        case success(text: String, isCached: Bool)
        /// Device ineligible or Apple Intelligence disabled, or preference off.
        case unavailable
        /// No previous same-routine session exists, or too few completed sets.
        case insufficientData
        /// Generation threw a non-guardrail error.
        case error
    }

    private(set) var state: AnalysisState = .idle

    // MARK: - Private

    private let logger = Logger(subsystem: "app.gymstreak.aicoach", category: "WorkoutAnalysisVM")
    private let aggregator = WorkoutAnalysisAggregator()
    private var streamTask: Task<Void, Never>?

    // MARK: - Public API

    /// Checks the disk cache silently. If a cached narrative exists, transitions
    /// directly to `.success` without user interaction.
    func checkCache(workout: WorkoutSession) {
        guard AICoachPreferences.shared.isWorkoutDetailEffectivelyEnabled,
              AICoachAvailability.shared.isAvailable else { return }

        if let cached = AICoachCache.shared.loadWorkoutAnalysis(workoutId: workout.id) {
            logger.debug("Cache hit for workout analysis \(workout.id, privacy: .private)")
            state = .success(text: cached.narrative, isCached: true)
        }
    }

    /// Generates a workout analysis, using cache if available.
    /// Fire-and-forget: cancels any in-flight stream before starting a new one.
    func generate(workout: WorkoutSession, locale: Locale, modelContext: ModelContext) {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            await self?.run(workout: workout, locale: locale, modelContext: modelContext, bypassCache: false)
        }
    }

    /// Forces a fresh generation, ignoring any cached result.
    /// Fire-and-forget: cancels any in-flight stream before starting a new one.
    func regenerate(workout: WorkoutSession, locale: Locale, modelContext: ModelContext) {
        streamTask?.cancel()
        AICoachCache.shared.invalidateWorkoutAnalysis(workoutId: workout.id)
        streamTask = Task { [weak self] in
            await self?.run(workout: workout, locale: locale, modelContext: modelContext, bypassCache: true)
        }
    }

    /// Cancels any in-flight stream. Call on view disappear.
    func cancel() {
        streamTask?.cancel()
        streamTask = nil
    }

    // MARK: - Core pipeline

    private func run(
        workout: WorkoutSession,
        locale: Locale,
        modelContext: ModelContext,
        bypassCache: Bool
    ) async {
        // 1. Availability check
        guard await isAvailable() else {
            state = .unavailable
            return
        }

        // 2. Preferences check
        guard AICoachPreferences.shared.isWorkoutDetailEffectivelyEnabled else {
            state = .unavailable
            return
        }

        // 3. Cache hit (skipped when bypassing)
        if !bypassCache {
            if let cached = AICoachCache.shared.loadWorkoutAnalysis(workoutId: workout.id) {
                logger.debug("Cache hit for workout analysis \(workout.id, privacy: .private)")
                state = .success(text: cached.narrative, isCached: true)
                return
            }
        }

        // 4. Aggregate input — returns nil when insufficient data
        guard let input = aggregator.buildInput(
            session: workout,
            locale: locale,
            modelContext: modelContext
        ) else {
            logger.debug("Insufficient data for workout analysis \(workout.routineName, privacy: .private)")
            state = .insufficientData
            return
        }

        // 5. Stream
        await stream(input: input, workoutId: workout.id)
    }

    // MARK: - Availability helper

    private func isAvailable() async -> Bool {
        let availability = AICoachAvailability.shared
        switch availability.state {
        case .available:
            return true
        case .deviceNotEligible, .appleIntelligenceNotEnabled:
            return false
        case .modelNotReady, .unknown:
            try? await Task.sleep(for: .seconds(2))
            await availability.refresh()
            return availability.isAvailable
        }
    }

    // MARK: - Guardrail detection

    /// Checks whether an error is guardrail-related, including cases where
    /// the `.guardrailViolation` enum case does not match directly but the
    /// error description contains safety-related phrases.
    private static func isGuardrailRelated(_ error: Error) -> Bool {
        if let gen = error as? LanguageModelSession.GenerationError {
            switch gen {
            case .guardrailViolation:
                return true
            default:
                break
            }
        }
        let desc = error.localizedDescription.lowercased()
        return desc.contains("unsafe") || desc.contains("guardrail") || desc.contains("safety")
    }

    // MARK: - Streaming

    private func stream(input: WorkoutAnalysisInput, workoutId: UUID) async {
        let start = ContinuousClock.now

        do {
            guard let responseStream = try await AICoachService.shared.streamWorkoutAnalysis(input: input) else {
                state = .unavailable
                return
            }

            var finalText = ""
            for try await snapshot in responseStream {
                guard !Task.isCancelled else { break }
                let partial = snapshot.content.narrative ?? ""
                finalText = partial
                state = .streaming(text: partial)
            }

            // If cancelled mid-stream, do not surface partial output.
            guard !Task.isCancelled else { return }

            // Stream complete
            state = .success(text: finalText, isCached: false)

            AICoachCache.shared.saveWorkoutAnalysis(
                workoutId: workoutId,
                output: WorkoutAnalysisOutput(narrative: finalText)
            )

            let elapsed = ContinuousClock.now - start
            let ms = Int(Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15)
            AICoachTelemetry.recordGeneration(
                useCase: "workout_analysis",
                durationMs: ms,
                inputTokens: nil,
                outputTokens: nil,
                success: true
            )

        } catch let error as LanguageModelSession.GenerationError {
            let elapsed = ContinuousClock.now - start
            let ms = Int(Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15)

            if Self.isGuardrailRelated(error) {
                // Silent fallback — no scary error shown to the user
                logger.warning("workout_analysis guardrail violation — falling back silently")
                AICoachTelemetry.recordGeneration(
                    useCase: "workout_analysis",
                    durationMs: ms,
                    inputTokens: nil,
                    outputTokens: nil,
                    success: false
                )
                state = .unavailable
            } else {
                logger.error("workout_analysis generation error: \(error.localizedDescription, privacy: .public)")
                AICoachTelemetry.recordError(
                    useCase: "workout_analysis",
                    errorTypeName: String(describing: type(of: error))
                )
                state = .error
            }

        } catch {
            let elapsed = ContinuousClock.now - start
            let ms = Int(Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15)

            // Some guardrail errors surface as non-GenerationError types
            if Self.isGuardrailRelated(error) {
                logger.warning("workout_analysis guardrail-like error — falling back silently")
                state = .unavailable
            } else {
                logger.error("workout_analysis unexpected error: \(error.localizedDescription, privacy: .public)")
                state = .error
            }

            AICoachTelemetry.recordError(
                useCase: "workout_analysis",
                errorTypeName: String(describing: type(of: error))
            )
            AICoachTelemetry.recordGeneration(
                useCase: "workout_analysis",
                durationMs: ms,
                inputTokens: nil,
                outputTokens: nil,
                success: false
            )
        }
    }
}
