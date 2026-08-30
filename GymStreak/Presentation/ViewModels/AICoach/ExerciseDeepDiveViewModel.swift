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
import FoundationModels
import os

/// Orchestrates exercise deep-dive generation for `ExerciseProgressChartView`.
///
/// Lifecycle:
/// 1. `checkCache(exerciseId:usage:)` runs from the screen's `.task(id:)`. If a cached
///    result exists for the current exercise + usage + last-set timestamp, the state
///    transitions straight to `.success(narrative:isCached:true)`.
/// 2. If no cache hit, the view renders `CoachDeepDiveButton`. Tapping it calls
///    `generate(exerciseId:exerciseName:usage:locale:)`.
/// 3. `regenerate(...)` bypasses the cache and forces a fresh generation.
///
/// **No `ModelContext` reaches this type.** Every history read goes through
/// `ExerciseDeepDiveFactProviding`, whose conformer answers on a model actor — this is a
/// `@MainActor` class, and both reads walk all of completed history (ticket 02, and Hard
/// rule 1 of the architecture: no `FetchDescriptor` in `Presentation/`).
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
        /// Model is streaming; the narrative fills paragraph by paragraph.
        case streaming(narrative: ExerciseDeepDiveNarrative)
        /// Generation complete; the narrative holds every paragraph.
        case success(narrative: ExerciseDeepDiveNarrative, isCached: Bool)
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
    private var streamTask: Task<Void, Never>?

    private let facts: any ExerciseDeepDiveFactProviding
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
    // `allowanceGate` and `facts` have no such default: the gate carries the
    // entitlement and the paywall seam, and `facts` is the model-actor-backed
    // history boundary. Per Hard rule 2 both come from `AppDependencies` and
    // never from a singleton.
    init(
        allowanceGate: AICoachAllowanceGate,
        facts: any ExerciseDeepDiveFactProviding,
        service: AICoachServicing? = nil,
        cache: AICoachCaching? = nil,
        preferences: AICoachPreferencesProviding? = nil,
        availability: AICoachAvailabilityProviding? = nil
    ) {
        self.allowanceGate = allowanceGate
        self.facts = facts
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
    ///
    /// Never spends an allowance unit and never aggregates: it asks the read boundary for
    /// the cache timestamp alone, which is a bounded probe rather than a walk of history.
    func checkCache(exerciseId: UUID, usage: DeepDiveUsage) async {
        guard preferences.isExerciseDeepDiveEffectivelyEnabled,
              availability.isAvailable else { return }

        guard let timestamp = await facts.fetchDeepDiveCacheTimestamp(
            exerciseId: exerciseId,
            usageSelection: usage.selection
        ) else { return }

        let key = Self.cacheKey(
            exerciseId: exerciseId,
            usageSelection: usage.selection,
            timestamp: timestamp
        )
        if let cached = cache.loadExerciseDeepDive(key: key) {
            logger.debug("Cache hit for exercise deep-dive \(exerciseId, privacy: .private)")
            state = .success(narrative: cached, isCached: true)
        }
    }

    /// Generates a deep-dive narrative for the exercise, using cache if available.
    /// Fire-and-forget: cancels any in-flight stream before starting a new one.
    /// Transitions to `.preparing` synchronously so the UI responds to the tap immediately.
    ///
    /// Takes the exercise as `id` + `name` rather than the `@Model`: the aggregation runs
    /// on a model actor, which a `PersistentModel` may not cross onto.
    ///
    /// Returns `false` when the free monthly allowance is spent — the gate has
    /// raised `.exerciseDeepDive` and the state is left untouched, so the "Ask
    /// the Coach" button stays where it was rather than collapsing into an
    /// empty surface behind the paywall.
    /// - Parameter weightUnit: the reader's unit, read from `\.weightUnit` by the view
    ///   that calls this — the same way `locale` arrives. See
    ///   docs/weight-unit-preference.md §13.
    @discardableResult
    func generate(
        exerciseId: UUID,
        exerciseName: String,
        usage: DeepDiveUsage,
        locale: Locale,
        weightUnit: WeightUnit
    ) -> Bool {
        guard let ticket = allowanceGate.requestGeneration() else { return false }
        start(
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            usage: usage,
            locale: locale,
            weightUnit: weightUnit,
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
    /// for both on screen and on disk (§7 Rule 4). The invalidation itself happens
    /// inside `run`, off the back of the one aggregate this generation fetches —
    /// computing the key here would mean a second walk of history for the same answer.
    @discardableResult
    func regenerate(
        exerciseId: UUID,
        exerciseName: String,
        usage: DeepDiveUsage,
        locale: Locale,
        weightUnit: WeightUnit
    ) -> Bool {
        guard let ticket = allowanceGate.requestGeneration() else { return false }
        start(
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            usage: usage,
            locale: locale,
            weightUnit: weightUnit,
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
        exerciseId: UUID,
        exerciseName: String,
        usage: DeepDiveUsage,
        locale: Locale,
        weightUnit: WeightUnit,
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
                exerciseId: exerciseId,
                exerciseName: exerciseName,
                usage: usage,
                locale: locale,
                weightUnit: weightUnit,
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
        exerciseId: UUID,
        exerciseName: String,
        usage: DeepDiveUsage,
        locale: Locale,
        weightUnit: WeightUnit,
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

        // 3. One walk of history, on the model actor, answering both questions this
        //    generation asks of it: which key describes the body of work, and what it
        //    says. The key is then carried through the cache check, the invalidation and
        //    the post-stream save — three uses, one fetch. Before ticket 02 each of those
        //    re-fetched all of history, on the main actor.
        let aggregate = await facts.fetchDeepDiveAggregate(
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            usage: usage,
            locale: locale,
            weightUnit: weightUnit
        )
        // A superseded generation must write no state: `start` cancels the previous
        // stream task and then sets `.preparing` for the new one, so a late
        // `.insufficientData` from the old task would land on top of it. The `defer`
        // above still returns the allowance unit.
        guard !Task.isCancelled else { return }

        let key = aggregate.lastCompletedSetTimestamp.map {
            Self.cacheKey(exerciseId: exerciseId, usageSelection: usage.selection, timestamp: $0)
        }

        // 4. Cache — bypassed by `regenerate`, which retires the stored narrative instead.
        if bypassCache {
            if let key { cache.invalidateExerciseDeepDive(key: key) }
        } else if let key, let cached = cache.loadExerciseDeepDive(key: key) {
            logger.debug("Cache hit for exercise deep-dive \(exerciseId, privacy: .private)")
            state = .success(narrative: cached, isCached: true)
            return
        }

        // 5. Insufficient data — the aggregate carries no input
        guard let input = aggregate.input else {
            logger.debug("Insufficient data for exercise deep-dive \(exerciseName, privacy: .private)")
            state = .insufficientData
            return
        }

        // 6. Stream
        if await stream(input: input, weightUnit: weightUnit, cacheKey: key) {
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
    /// - Parameter cacheKey: the key this narrative is stored under, already resolved
    ///   from the same aggregate that produced `input` — so the sentences and the
    ///   timestamp they are keyed by describe one and the same body of work. `nil` when
    ///   history held no completed set to stamp it with, in which case nothing is stored.
    @discardableResult
    private func stream(
        input: ExerciseDeepDiveInput,
        weightUnit: WeightUnit,
        cacheKey: String?
    ) async -> Bool {
        let start = ContinuousClock.now

        do {
            guard let responseStream = try await service.streamExerciseDeepDive(
                input: input,
                weightUnit: weightUnit
            ) else {
                state = .unavailable
                return false
            }

            // Composed in Swift from the same aggregate, and available before the first
            // token — so the surface has one real line while the paragraphs are still
            // skeletons. The model never receives the facts behind it.
            let peakSentence = input.peakSentence(in: weightUnit)
            // A blended view has no progression, so it gets no progression paragraph —
            // whatever the model returns for that field. The prompt and the field's
            // `@Guide` both tell it to omit the field; this is the half of the guarantee
            // that does not depend on it obeying.
            let statesProgression = input.blendedUsageCount <= 1

            var narrative = ExerciseDeepDiveNarrative(peakSentence: peakSentence)
            for try await snapshot in responseStream {
                guard !Task.isCancelled else { break }
                narrative = ExerciseDeepDiveNarrative(
                    partial: snapshot.content,
                    peakSentence: peakSentence,
                    statesProgression: statesProgression
                )
                state = .streaming(narrative: narrative)
            }

            // If cancelled mid-stream, do not surface partial output.
            guard !Task.isCancelled else { return false }

            // Stream complete
            state = .success(narrative: narrative, isCached: false)

            // Persist to cache keyed by (exerciseId, usage, last-set timestamp)
            if let cacheKey {
                cache.saveExerciseDeepDive(key: cacheKey, narrative: narrative)
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
    ///
    /// Pure string assembly: the timestamp is fetched once per interaction by the caller
    /// (`ExerciseDeepDiveFactProviding`) and handed in, never re-read here.
    static func cacheKey(
        exerciseId: UUID,
        usageSelection: ExerciseUsageSelection,
        timestamp: Date
    ) -> String {
        "\(exerciseId.uuidString)|\(usageSelection.cacheToken)|\(iso8601.string(from: timestamp))"
    }

    /// Hoisted: `ISO8601DateFormatter` is expensive to allocate and this runs on every
    /// cache check, generation and save.
    private static let iso8601 = ISO8601DateFormatter()
}
