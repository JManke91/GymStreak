//
//  ExerciseDeepDiveViewModel.swift
//  GymStreak
//
//  Orchestrates AI Coach exercise deep-dive generation.
//  Handles availability checks, preferences gating, caching,
//  streaming, and graceful degradation — all AI logic stays
//  out of the view layer.
//
//  Since ticket 09 a fresh generation also spends the free monthly taster
//  (P5, docs/pro-subscription.md §5e). Re-reading a cached narrative does not.
//

import Foundation
import SwiftData
import FoundationModels
import os

/// Orchestrates exercise deep-dive generation for `ExerciseProgressChartView`.
///
/// Lifecycle:
/// 1. `checkCache(exercise:usage:locale:modelContext:)` runs from the screen's
///    `.task(id:)`. If a cached result exists for the current exercise + usage +
///    last-set timestamp, the state transitions straight to `.success(text:isCached:true)`.
/// 2. If no cache hit, the view renders `CoachDeepDiveButton`. Tapping it calls
///    `generate(exercise:usage:locale:modelContext:)`.
/// 3. `regenerate(...)` bypasses the cache and forces a fresh generation.
///
/// **Every entry point takes the usage the screen is showing.** The narrative describes
/// one usage, so it is cached per usage and generated per usage; there is deliberately no
/// default, because a caller that forgets it would silently narrate the blend the chart
/// above it refuses to draw.
///
/// Steps 2 and 3 pass through `AICoachAllowanceGate` (P5, one free generation
/// per calendar month); step 1 never does — a narrative already generated is
/// free to re-read forever, in every entitlement state.
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
    private let allowanceGate: AICoachAllowanceGate

    // MARK: - Init

    // Defaults are resolved inside the @MainActor-isolated init body — a
    // `= Foo.shared` default argument would be evaluated in a nonisolated
    // context (error under Swift 6 language mode).
    //
    // `allowanceGate` has no such default: it carries the entitlement and the
    // paywall seam, which per Hard rule 2 come from `AppDependencies` and never
    // from a singleton.
    init(
        allowanceGate: AICoachAllowanceGate,
        service: AICoachServicing? = nil,
        cache: AICoachCaching? = nil,
        preferences: AICoachPreferencesProviding? = nil,
        availability: AICoachAvailabilityProviding? = nil
    ) {
        self.allowanceGate = allowanceGate
        self.service = service ?? AICoachService.shared
        self.cache = cache ?? AICoachCache.shared
        self.preferences = preferences ?? AICoachPreferences.shared
        self.availability = availability ?? AICoachAvailability.shared
    }

    // MARK: - Free-tier allowance

    /// The §8 placement D hint, or `nil` when none belongs on screen.
    ///
    /// Computed, not stored: the gate reads the `@Observable` entitlement
    /// provider inside it, so a purchase or a lapse removes or restores the
    /// hint with no reload.
    var allowanceNudge: AIAllowanceNudge? {
        AIAllowanceNudge(
            state: allowanceGate.nudgeState,
            remainingFormat: "ai_coach.deep_dive.allowance.nudge".localized,
            exhaustedText: "ai_coach.deep_dive.allowance.nudge.exhausted".localized
        )
    }

    // MARK: - Public API

    /// Checks the disk cache silently. If a cached narrative exists, transitions
    /// directly to `.success` without user interaction.
    func checkCache(
        exercise: Exercise,
        usage: DeepDiveUsage,
        locale: Locale,
        modelContext: ModelContext
    ) async {
        guard preferences.isExerciseDeepDiveEffectivelyEnabled,
              availability.isAvailable else { return }

        guard let key = cacheKey(
            exerciseId: exercise.id,
            usageSelection: usage.selection,
            modelContext: modelContext
        ) else { return }

        if let cached = cache.loadExerciseDeepDive(key: key) {
            logger.debug("Cache hit for exercise deep-dive \(exercise.id, privacy: .private)")
            state = .success(text: cached.narrative, isCached: true)
        }
    }

    /// Generates a deep-dive narrative for `exercise`, using cache if available.
    /// Fire-and-forget: cancels any in-flight stream before starting a new one.
    /// Transitions to `.preparing` synchronously so the UI responds to the tap immediately.
    ///
    /// Returns `false` when the free monthly allowance is spent — the gate has
    /// raised `.exerciseDeepDive` and the state is left untouched, so the "Ask
    /// the Coach" button stays where it was rather than collapsing into an
    /// empty surface behind the paywall.
    @discardableResult
    func generate(
        exercise: Exercise,
        usage: DeepDiveUsage,
        locale: Locale,
        modelContext: ModelContext
    ) -> Bool {
        guard let ticket = allowanceGate.requestGeneration() else { return false }
        start(
            exercise: exercise,
            usage: usage,
            locale: locale,
            modelContext: modelContext,
            bypassCache: false,
            ticket: ticket
        )
        return true
    }

    /// Forces a fresh generation, ignoring any cached result.
    /// Fire-and-forget: cancels any in-flight stream before starting a new one.
    ///
    /// The gate is asked **before** the cache is invalidated: a refused
    /// regeneration must leave the narrative the user already paid an allowance
    /// for both on screen and on disk (§7 Rule 4).
    @discardableResult
    func regenerate(
        exercise: Exercise,
        usage: DeepDiveUsage,
        locale: Locale,
        modelContext: ModelContext
    ) -> Bool {
        guard let ticket = allowanceGate.requestGeneration() else { return false }
        if let key = cacheKey(
            exerciseId: exercise.id,
            usageSelection: usage.selection,
            modelContext: modelContext
        ) {
            cache.invalidateExerciseDeepDive(key: key)
        }
        start(
            exercise: exercise,
            usage: usage,
            locale: locale,
            modelContext: modelContext,
            bypassCache: true,
            ticket: ticket
        )
        return true
    }

    /// Starts the stream for an already-admitted generation.
    ///
    /// The task captures the **gate** strongly alongside `[weak self]`, like the
    /// chat's refund closure does: if this `@State`-owned ViewModel is gone
    /// before the task body runs, the reserved unit still has to find its way
    /// back to the user. The gate holds only app-lifetime collaborators, so a
    /// strong capture neither leaks nor cycles.
    private func start(
        exercise: Exercise,
        usage: DeepDiveUsage,
        locale: Locale,
        modelContext: ModelContext,
        bypassCache: Bool,
        ticket: AICoachAllowanceGate.Ticket
    ) {
        streamTask?.cancel()
        state = .preparing
        streamTask = Task { [weak self, gate = allowanceGate] in
            guard let self else {
                gate.refund(ticket)
                return
            }
            await self.run(
                exercise: exercise,
                usage: usage,
                locale: locale,
                modelContext: modelContext,
                bypassCache: bypassCache,
                ticket: ticket
            )
        }
    }

    /// Cancels any in-flight stream. Call on view disappear.
    func cancel() {
        streamTask?.cancel()
        streamTask = nil
    }

#if DEBUG
    /// Test hook: awaits the in-flight generation so a test can assert on the
    /// terminal state (and on what the allowance was charged) instead of
    /// polling `Task.yield()`. Generation is fire-and-forget by design — the
    /// tap must return immediately — which is why this is a hook rather than
    /// an `await` inside `generate`.
    func waitForCurrentGeneration() async {
        await streamTask?.value
    }
#endif

    // MARK: - Core pipeline

    /// - Parameter ticket: the admitted generation. Every exit that does not
    ///   produce a narrative gives its unit back — an unavailable model, the
    ///   preference switched off mid-flight, a cache hit that arrived first, an
    ///   exercise with too little data, a failed or cancelled stream. Only a
    ///   completed narrative keeps it.
    private func run(
        exercise: Exercise,
        usage: DeepDiveUsage,
        locale: Locale,
        modelContext: ModelContext,
        bypassCache: Bool,
        ticket: AICoachAllowanceGate.Ticket
    ) async {
        var pending: AICoachAllowanceGate.Ticket? = ticket
        defer { if let pending { allowanceGate.refund(pending) } }

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
            if let key = cacheKey(
                exerciseId: exercise.id,
                usageSelection: usage.selection,
                modelContext: modelContext
               ),
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
            modelContext: modelContext,
            usage: usage
        ) else {
            logger.debug("Insufficient data for exercise deep-dive \(exercise.name, privacy: .private)")
            state = .insufficientData
            return
        }

        // 5. Stream
        if await stream(
            input: input,
            exerciseId: exercise.id,
            usageSelection: usage.selection,
            modelContext: modelContext
        ) {
            pending = nil
        }
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

    /// - Returns: `true` only when a complete narrative reached the screen. The
    ///   caller keeps the allowance unit on `true` and refunds it otherwise —
    ///   a cancelled stream surfaces no text, so it costs nothing either.
    @discardableResult
    private func stream(
        input: ExerciseDeepDiveInput,
        exerciseId: UUID,
        usageSelection: ExerciseUsageSelection,
        modelContext: ModelContext
    ) async -> Bool {
        let start = ContinuousClock.now

        do {
            guard let responseStream = try await service.streamExerciseDeepDive(input: input) else {
                state = .unavailable
                return false
            }

            var finalText = ""
            for try await snapshot in responseStream {
                guard !Task.isCancelled else { break }
                let partial = snapshot.content.narrative ?? ""
                finalText = partial
                state = .streaming(text: partial)
            }

            // If cancelled mid-stream, do not surface partial output.
            guard !Task.isCancelled else { return false }

            // Stream complete
            state = .success(text: finalText, isCached: false)

            // Persist to cache keyed by (exerciseId, usage, last-set timestamp)
            if let key = cacheKey(
                exerciseId: exerciseId,
                usageSelection: usageSelection,
                modelContext: modelContext
            ) {
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
            return true

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

        return false
    }

    // MARK: - Cache key

    /// Builds the cache key `"\(exerciseId)|\(usageToken)|\(lastSetTimestampISO)"`.
    /// Returns `nil` when no completed sets are found (key would be meaningless).
    ///
    /// **The usage is part of the key because it is part of the narrative.** The
    /// deep-dive describes the usage the screen is showing, so two usages of one exercise
    /// are two different narratives; without the token, switching usage would serve the
    /// previous usage's sentences under the new usage's chart. Switching back is then a
    /// cache *hit* rather than a second `regenerate`, which for a free user is a second
    /// monthly allowance unit (`docs/pro-subscription.md` §5e).
    ///
    /// The timestamp is resolved for that same usage, so logging a set of one usage does
    /// not invalidate another usage's narrative — its history did not change.
    func cacheKey(
        exerciseId: UUID,
        usageSelection: ExerciseUsageSelection,
        modelContext: ModelContext
    ) -> String? {
        guard let timestamp = aggregator.lastCompletedSetTimestamp(
            exerciseId: exerciseId,
            modelContext: modelContext,
            usageSelection: usageSelection
        ) else {
            return nil
        }
        return "\(exerciseId.uuidString)|\(usageSelection.cacheToken)|\(Self.iso8601.string(from: timestamp))"
    }

    /// Hoisted: `ISO8601DateFormatter` is expensive to allocate and this runs on every
    /// cache check, generation and save.
    private static let iso8601 = ISO8601DateFormatter()
}
