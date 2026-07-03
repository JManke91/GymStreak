//
//  ExerciseDeepDiveViewModel.swift
//  GymStreak
//
//  Orchestrates AI Coach exercise deep-dive generation.
//  Handles availability checks, preferences gating, caching,
//  streaming, and graceful degradation — all AI logic stays
//  out of the view layer.
//

import Foundation
import SwiftData
import FoundationModels
import os

/// Orchestrates exercise deep-dive generation for `ExerciseProgressChartView`.
///
/// Lifecycle:
/// 1. `checkCache(exercise:locale:modelContext:)` is called on `.onAppear`.
///    If a cached result exists for the current exercise + last-set timestamp, the
///    state transitions directly to `.success(text:isCached:true)`.
/// 2. If no cache hit, the view renders `CoachDeepDiveButton`. Tapping it calls
///    `generate(exercise:locale:modelContext:)`.
/// 3. `regenerate(...)` bypasses the cache and forces a fresh generation.
@Observable
@MainActor
final class ExerciseDeepDiveViewModel {

    // MARK: - State

    enum DeepDiveState: Equatable {
        /// Initial — nothing shown yet.
        case idle
        /// Generation kicked off but no tokens received yet — surface shows a skeleton.
        case preparing
        /// Model is streaming; associated text grows incrementally.
        case streaming(text: String)
        /// Generation complete; text contains the full narrative.
        case success(text: String, isCached: Bool)
        /// Device ineligible or Apple Intelligence disabled, or preference off.
        case unavailable
        /// Aggregator returned nil — exercise has fewer than 4 completed sets.
        case insufficientData
        /// Generation threw a non-guardrail error.
        case error
    }

    private(set) var state: DeepDiveState = .idle

    // MARK: - Private

    private let logger = Logger(subsystem: "app.gymstreak.aicoach", category: "ExerciseDeepDiveVM")
    private let aggregator = ExerciseDeepDiveAggregator()
    private var streamTask: Task<Void, Never>?

    private let service: AICoachServicing
    private let cache: AICoachCaching
    private let preferences: AICoachPreferencesProviding
    private let availability: AICoachAvailabilityProviding

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

    /// Checks the disk cache silently. If a cached narrative exists, transitions
    /// directly to `.success` without user interaction.
    func checkCache(exercise: Exercise, locale: Locale, modelContext: ModelContext) async {
        guard preferences.isExerciseDeepDiveEffectivelyEnabled,
              availability.isAvailable else { return }

        guard let key = cacheKey(exerciseId: exercise.id, modelContext: modelContext) else { return }

        if let cached = cache.loadExerciseDeepDive(key: key) {
            logger.debug("Cache hit for exercise deep-dive \(exercise.id, privacy: .private)")
            state = .success(text: cached.narrative, isCached: true)
        }
    }

    /// Generates a deep-dive narrative for `exercise`, using cache if available.
    /// Fire-and-forget: cancels any in-flight stream before starting a new one.
    /// Transitions to `.preparing` synchronously so the UI responds to the tap immediately.
    func generate(exercise: Exercise, locale: Locale, modelContext: ModelContext) {
        streamTask?.cancel()
        state = .preparing
        streamTask = Task { [weak self] in
            await self?.run(exercise: exercise, locale: locale, modelContext: modelContext, bypassCache: false)
        }
    }

    /// Forces a fresh generation, ignoring any cached result.
    /// Fire-and-forget: cancels any in-flight stream before starting a new one.
    func regenerate(exercise: Exercise, locale: Locale, modelContext: ModelContext) {
        streamTask?.cancel()
        state = .preparing
        if let key = cacheKey(exerciseId: exercise.id, modelContext: modelContext) {
            cache.invalidateExerciseDeepDive(key: key)
        }
        streamTask = Task { [weak self] in
            await self?.run(exercise: exercise, locale: locale, modelContext: modelContext, bypassCache: true)
        }
    }

    /// Cancels any in-flight stream. Call on view disappear.
    func cancel() {
        streamTask?.cancel()
        streamTask = nil
    }

    // MARK: - Core pipeline

    private func run(
        exercise: Exercise,
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
        guard preferences.isExerciseDeepDiveEffectivelyEnabled else {
            state = .unavailable
            return
        }

        // 3. Cache hit (skipped when bypassing)
        if !bypassCache {
            if let key = cacheKey(exerciseId: exercise.id, modelContext: modelContext),
               let cached = cache.loadExerciseDeepDive(key: key) {
                logger.debug("Cache hit for exercise deep-dive \(exercise.id, privacy: .private)")
                state = .success(text: cached.narrative, isCached: true)
                return
            }
        }

        // 4. Aggregate input — returns nil when insufficient data
        guard let input = aggregator.buildInput(
            exercise: exercise,
            locale: locale,
            modelContext: modelContext
        ) else {
            logger.debug("Insufficient data for exercise deep-dive \(exercise.name, privacy: .private)")
            state = .insufficientData
            return
        }

        // 5. Stream
        await stream(input: input, exerciseId: exercise.id, modelContext: modelContext)
    }

    // MARK: - Availability helper

    private func isAvailable() async -> Bool {
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

    // MARK: - Streaming

    private func stream(
        input: ExerciseDeepDiveInput,
        exerciseId: UUID,
        modelContext: ModelContext
    ) async {
        let start = ContinuousClock.now

        do {
            guard let responseStream = try await service.streamExerciseDeepDive(input: input) else {
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

            // Persist to cache keyed by (exerciseId, last-set timestamp)
            if let key = cacheKey(exerciseId: exerciseId, modelContext: modelContext) {
                cache.saveExerciseDeepDive(
                    key: key,
                    output: ExerciseDeepDiveOutput(narrative: finalText)
                )
            }

            let elapsed = ContinuousClock.now - start
            let ms = Int(Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15)
            AICoachTelemetry.recordGeneration(
                useCase: "exercise_deep_dive",
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
                logger.warning("exercise_deep_dive guardrail violation — falling back silently")
                AICoachTelemetry.recordGeneration(
                    useCase: "exercise_deep_dive",
                    durationMs: ms,
                    inputTokens: nil,
                    outputTokens: nil,
                    success: false
                )
                state = .unavailable
            default:
                logger.error("exercise_deep_dive generation error: \(error.localizedDescription, privacy: .public)")
                AICoachTelemetry.recordError(
                    useCase: "exercise_deep_dive",
                    errorTypeName: String(describing: type(of: error))
                )
                state = .error
            }

        } catch {
            let elapsed = ContinuousClock.now - start
            let ms = Int(Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15)
            logger.error("exercise_deep_dive unexpected error: \(error.localizedDescription, privacy: .public)")
            AICoachTelemetry.recordError(
                useCase: "exercise_deep_dive",
                errorTypeName: String(describing: type(of: error))
            )
            AICoachTelemetry.recordGeneration(
                useCase: "exercise_deep_dive",
                durationMs: ms,
                inputTokens: nil,
                outputTokens: nil,
                success: false
            )
            state = .error
        }
    }

    // MARK: - Cache key

    /// Builds the cache key `"\(exerciseId)|\(lastSetTimestampISO)"`.
    /// Returns `nil` when no completed sets are found (key would be meaningless).
    func cacheKey(exerciseId: UUID, modelContext: ModelContext) -> String? {
        guard let timestamp = aggregator.lastCompletedSetTimestamp(exerciseId: exerciseId, modelContext: modelContext) else {
            return nil
        }
        let iso = ISO8601DateFormatter().string(from: timestamp)
        return "\(exerciseId.uuidString)|\(iso)"
    }
}
