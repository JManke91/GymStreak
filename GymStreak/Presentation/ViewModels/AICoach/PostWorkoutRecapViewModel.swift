//
//  PostWorkoutRecapViewModel.swift
//  GymStreak
//
//  Orchestrates AI-powered post-workout recap generation.
//  Manages availability checks, data threshold gating, caching, streaming,
//  and graceful degradation — keeping all AI logic out of the view layer.
//

import Foundation
import SwiftData
import FoundationModels
import os

/// Orchestrates post-workout recap generation for the SaveWorkoutView.
///
/// Lifecycle:
/// 1. `generate(session:locale:modelContext:)` is called from `.task` in `SaveWorkoutView`.
/// 2. The VM checks availability + preferences, gates on insufficient data, then streams.
/// 3. `regenerate(...)` bypasses the cache and forces a fresh generation.
@Observable
@MainActor
final class PostWorkoutRecapViewModel {

    // MARK: - State

    enum RecapState: Equatable {
        /// Initial — nothing shown yet.
        case idle
        /// Model is streaming; associated text grows incrementally.
        case streaming(text: String)
        /// Generation complete; shows the final narrative.
        case success(text: String)
        /// Device ineligible or Apple Intelligence disabled.
        case unavailable
        /// Not enough prior sessions to compare against.
        case insufficientData
        /// Generation threw a non-guardrail error.
        case error
    }

    private(set) var state: RecapState = .idle

    // MARK: - Private

    private let logger = Logger(subsystem: "app.gymstreak.aicoach", category: "PostWorkoutRecapVM")
    private let aggregator = PostWorkoutRecapAggregator()

    private let service: AICoachServicing
    private let cache: AICoachCaching
    private let preferences: AICoachPreferencesProviding
    private let availability: AICoachAvailabilityProviding

    /// Minimum completed sets in the current session before generation is attempted.
    private let minimumSetsThreshold = 2
    /// Minimum prior sessions required for comparison content.
    private let minimumPriorSessionsThreshold = 2

    // MARK: - Init

    // Defaults are resolved inside the @MainActor-isolated init body — a
    // `= Foo.shared` default argument would be evaluated in a nonisolated
    // context (error under Swift 6 language mode).
    init(
        service: AICoachServicing? = nil,
        cache: AICoachCaching? = nil,
        preferences: AICoachPreferencesProviding? = nil,
        availability: AICoachAvailabilityProviding? = nil
    ) {
        self.service = service ?? AICoachService.shared
        self.cache = cache ?? AICoachCache.shared
        self.preferences = preferences ?? AICoachPreferences.shared
        self.availability = availability ?? AICoachAvailability.shared
    }

    // MARK: - Public API

    /// Discards the cached recap for `session`, if any. Called when the user cancels
    /// out of `SaveWorkoutView` before the session is persisted — the cache entry
    /// generated during that in-flight save would otherwise be orphaned.
    func discardCachedRecap(for session: WorkoutSession) {
        cache.invalidatePostWorkout(workoutId: session.id)
    }

    /// Generates a recap for `session`, using cache if available.
    func generate(
        session: WorkoutSession,
        locale: Locale,
        modelContext: ModelContext
    ) async {
        await run(session: session, locale: locale, modelContext: modelContext, bypassCache: false)
    }

    /// Forces a fresh generation, ignoring any cached result.
    func regenerate(
        session: WorkoutSession,
        locale: Locale,
        modelContext: ModelContext
    ) async {
        cache.invalidatePostWorkout(workoutId: session.id)
        await run(session: session, locale: locale, modelContext: modelContext, bypassCache: true)
    }

    // MARK: - Core pipeline

    private func run(
        session: WorkoutSession,
        locale: Locale,
        modelContext: ModelContext,
        bypassCache: Bool
    ) async {
        // 1. Availability check — with one retry for modelNotReady
        guard await isAvailable() else {
            state = .unavailable
            return
        }

        // 2. Preferences check
        guard preferences.isPostWorkoutEffectivelyEnabled else {
            state = .unavailable
            return
        }

        // 3. Data threshold — current session sets
        let completedSets = session.workoutExercisesList.flatMap(\.setsList).filter(\.isCompleted).count
        guard completedSets >= minimumSetsThreshold else {
            state = .insufficientData
            return
        }

        // 4. Data threshold — prior sessions
        let priorCount = aggregator.countPriorSessions(excludingSession: session, modelContext: modelContext)
        guard priorCount >= minimumPriorSessionsThreshold else {
            state = .insufficientData
            return
        }

        // 5. Cache hit (skipped when bypassing)
        if !bypassCache {
            if let cached = cache.loadPostWorkout(workoutId: session.id) {
                logger.debug("Cache hit for post-workout recap \(session.id, privacy: .private)")
                state = .success(text: cached.narrative)
                return
            }
        }

        // 6. Build aggregated input
        let input = aggregator.buildInput(session: session, locale: locale, modelContext: modelContext)

        // 7. Stream
        await stream(input: input, workoutId: session.id)
    }

    // MARK: - Availability helper

    /// Returns `true` when the device is ready.
    /// If state is `.modelNotReady`, retries once after 2 s.
    private func isAvailable() async -> Bool {
        switch availability.state {
        case .available:
            return true
        case .deviceNotEligible, .appleIntelligenceNotEnabled:
            return false
        case .modelNotReady, .unknown:
            // Single retry after a short delay
            try? await Task.sleep(for: .seconds(2))
            await availability.refresh()
            return availability.isAvailable
        }
    }

    // MARK: - Streaming

    private func stream(input: PostWorkoutRecapInput, workoutId: UUID) async {
        let start = ContinuousClock.now

        do {
            guard let responseStream = try await service.streamPostWorkoutRecap(input: input) else {
                // Service returned nil — disabled or unavailable
                state = .unavailable
                return
            }

            var finalText = ""
            for try await snapshot in responseStream {
                let partial = snapshot.content.narrative ?? ""
                finalText = partial
                state = .streaming(text: partial)
            }

            // Stream complete
            state = .success(text: finalText)
            cache.savePostWorkout(
                workoutId: workoutId,
                output: PostWorkoutRecapOutput(narrative: finalText)
            )

            let elapsed = ContinuousClock.now - start
            let ms = Int(Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15)
            AICoachTelemetry.recordGeneration(
                useCase: "post_workout",
                durationMs: ms,
                inputTokens: nil,
                outputTokens: nil,
                success: true
            )

        } catch let error as LanguageModelSession.GenerationError {
            let elapsed = ContinuousClock.now - start
            let ms = Int(Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15)

            switch error {
            case .guardrailViolation:
                // Silent fallback — no scary error shown to the user
                logger.warning("post_workout recap guardrail violation — falling back silently")
                AICoachTelemetry.recordGeneration(useCase: "post_workout", durationMs: ms, inputTokens: nil, outputTokens: nil, success: false)
                state = .unavailable
            default:
                logger.error("post_workout recap generation error: \(error.localizedDescription, privacy: .public)")
                AICoachTelemetry.recordError(useCase: "post_workout", errorTypeName: String(describing: type(of: error)))
                state = .error
            }

        } catch {
            let elapsed = ContinuousClock.now - start
            let ms = Int(Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15)
            logger.error("post_workout recap unexpected error: \(error.localizedDescription, privacy: .public)")
            AICoachTelemetry.recordError(useCase: "post_workout", errorTypeName: String(describing: type(of: error)))
            AICoachTelemetry.recordGeneration(useCase: "post_workout", durationMs: ms, inputTokens: nil, outputTokens: nil, success: false)
            state = .error
        }
    }
}
