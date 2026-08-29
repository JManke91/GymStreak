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
/// 4. `cancel()` stops the in-flight generation — on view disappear, and when the session
///    being recapped is discarded.
///
/// **The session is read only in the synchronous `start`, never in the task it spawns.**
/// `WorkoutViewModel.cancelWorkout()` deletes the in-progress session, and generation outlives
/// the screen that started it (the availability retry sleeps two seconds, streaming takes longer
/// still). Reading a deleted `@Model` is an uncatchable SwiftData `fatalError`, so everything the
/// generation needs is taken off `session` before the task exists, and only values cross into it.
/// See `docs/history-delete-race.md`.
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
    private var runTask: Task<Void, Never>?

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
    ///
    /// **Synchronous, and that is the point.** Every read of `session` happens here, in the
    /// caller's turn on the main actor. Discarding the workout deletes this very session, and
    /// a `Task` body is not ordered against the task that does the deleting (SE-0431 gives an
    /// implicitly-isolated closure no creation-order guarantee), so a session read inside the
    /// task could resume onto a tombstone — an uncatchable SwiftData `fatalError`. Only values
    /// go into the task. See `docs/history-delete-race.md`.
    ///
    /// The generation itself is fire-and-forget, like `WorkoutAnalysisViewModel`: the caller
    /// keeps no handle, so `cancel()` can stop it from anywhere — including the moment the
    /// session it describes is discarded, which is not the moment the view goes away.
    func generate(
        session: WorkoutSession,
        locale: Locale,
        modelContext: ModelContext
    ) {
        // `cancel()` rather than `runTask?.cancel()`: `start` returns without spawning a task
        // when it gates out, and a stale cancelled handle would then outlive it.
        cancel()
        start(session: session, locale: locale, modelContext: modelContext, bypassCache: false)
    }

    /// Forces a fresh generation, ignoring any cached result.
    func regenerate(
        session: WorkoutSession,
        locale: Locale,
        modelContext: ModelContext
    ) {
        cancel()
        cache.invalidatePostWorkout(workoutId: session.id)
        start(session: session, locale: locale, modelContext: modelContext, bypassCache: true)
    }

    /// Stops any in-flight generation. Called on view disappear, and when the session being
    /// recapped is discarded — after which nothing may read it again.
    func cancel() {
        runTask?.cancel()
        runTask = nil
    }

    // MARK: - Core pipeline

    /// The value-typed hand-off from the session-reading half to the streaming half.
    private struct PendingGeneration {
        let input: PostWorkoutRecapInput
        let workoutId: UUID
    }

    /// Gates on preferences, availability and data, then hands the streaming half nothing but
    /// values. Synchronous from start to finish — no `await` may be introduced between the
    /// gates, because the session reads below are only safe while nothing can interleave.
    private func start(
        session: WorkoutSession,
        locale: Locale,
        modelContext: ModelContext,
        bypassCache: Bool
    ) {
        // 1. Preferences check
        guard preferences.isPostWorkoutEffectivelyEnabled else {
            state = .unavailable
            return
        }

        // 2. Availability, synchronous verdicts only. The `.modelNotReady` / `.unknown`
        //    retry sleeps, so it moves into the streaming half — which means a not-yet-ready
        //    device pays the aggregation before learning it cannot use it, and an
        //    insufficient-data session on such a device now reports `.insufficientData`
        //    rather than `.unavailable`. Both are cheap trades for keeping every model read
        //    on this side of the first await.
        switch availability.state {
        case .deviceNotEligible, .appleIntelligenceNotEnabled:
            state = .unavailable
            return
        case .available, .modelNotReady, .unknown:
            break
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

        let workoutId = session.id

        // 5. Cache hit (skipped when bypassing)
        if !bypassCache {
            if let cached = cache.loadPostWorkout(workoutId: workoutId) {
                logger.debug("Cache hit for post-workout recap \(workoutId, privacy: .private)")
                state = .success(text: cached.narrative)
                return
            }
        }

        // 6. Build aggregated input — the last read of `session`.
        let pending = PendingGeneration(
            input: aggregator.buildInput(session: session, locale: locale, modelContext: modelContext),
            workoutId: workoutId
        )

        runTask = Task { [weak self] in await self?.run(pending) }
    }

    /// The asynchronous half: the availability retry the ineligible verdicts did not settle,
    /// then the stream. Touches no `@Model`.
    private func run(_ pending: PendingGeneration) async {
        let isReady = await isAvailable()
        // Cancellation first: a run stopped mid-retry describes a workout that is gone or a
        // screen that is, and neither wants a state write.
        guard !Task.isCancelled else { return }
        guard isReady else {
            state = .unavailable
            return
        }

        await stream(input: pending.input, workoutId: pending.workoutId)
    }

    // MARK: - Availability helper

    /// Returns `true` when the device is ready.
    /// If state is `.modelNotReady`, retries once after 2 s. The two verdicts that need no
    /// retry are already handled synchronously in `start`.
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

            // Cancelled runs describe a workout that is gone (discarded) or a screen that
            // is: neither should be cached or shown.
            guard !Task.isCancelled else { return }

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
