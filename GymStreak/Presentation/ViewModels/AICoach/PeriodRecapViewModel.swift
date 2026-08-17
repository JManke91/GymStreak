//
//  PeriodRecapViewModel.swift
//  GymStreak
//
//  Orchestrates AI period recap generation: cache lookup, streaming,
//  range switching, and graceful degradation.
//
//  Since ticket 09 a fresh generation also spends the free monthly taster
//  (P4, docs/pro-subscription.md §5e). Re-reading a cached recap does not, and
//  a metered user is never generated *for* — they are offered the generation
//  and tap it.
//

import Foundation
import SwiftData
import FoundationModels
import os

// MARK: - State

/// The view state for PeriodRecapView.
enum PeriodRecapState {
    /// Performing the initial cache/availability check.
    case loading
    /// Model is actively streaming; payload grows word-by-word.
    case streaming(PeriodRecapViewModel.PartialContent)
    /// Complete — may have been served from cache.
    case success(PeriodRecapOutput, isCached: Bool, generatedAt: Date, metrics: HeadlineMetrics?)
    /// Device not eligible for Apple Intelligence.
    case unavailable(HeadlineMetrics?)
    /// Fewer than 3 sessions in the period — no narrative generated.
    case insufficient(HeadlineMetrics)
    /// Unexpected generation error.
    case error(String)
    /// Free tier with allowance left: a fresh recap would spend the month's
    /// single generation, so the screen offers it and waits for a tap.
    /// Unreachable for a Pro user and while the kill switch is off.
    case offer(HeadlineMetrics?)
    /// Free tier with nothing left this month — the paywall has been raised and
    /// the screen shows the unlock affordance behind it.
    case gated(HeadlineMetrics?)
}

// MARK: - ViewModel

@Observable
@MainActor
final class PeriodRecapViewModel {

    // MARK: - Nested Types

    /// Partial streaming content mirror — updated every snapshot.
    struct PartialContent {
        var headline: String = ""
        var trendsNarrative: String = ""
        var correlationHighlight: String? = nil
        var closingSentence: String = ""
        var headlineMetrics: HeadlineMetrics?
    }

    // MARK: - Public Properties

    private(set) var state: PeriodRecapState = .loading
    private(set) var range: PeriodRange

    // MARK: - Private

    private let aggregator = PeriodRecapAggregator()
    private let logger = Logger(subsystem: "app.gymstreak.aicoach", category: "PeriodRecapVM")
    private var streamTask: Task<Void, Never>?

    private let service: AICoachServicing
    private let cache: AICoachCaching
    private let preferences: AICoachPreferencesProviding
    private let availability: AICoachAvailabilityProviding
    private let allowanceGate: AICoachAllowanceGate

    /// ISO8601 date formatter for building cache keys.
    private let isoFmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    // MARK: - Init

    // Defaults are resolved inside the @MainActor-isolated init body — a
    // `= Foo.shared` default argument would be evaluated in a nonisolated
    // context (error under Swift 6 language mode).
    //
    // `allowanceGate` has no such default: it carries the entitlement and the
    // paywall seam, which per Hard rule 2 come from `AppDependencies` and never
    // from a singleton.
    init(
        initialRange: PeriodRange,
        allowanceGate: AICoachAllowanceGate,
        service: AICoachServicing? = nil,
        cache: AICoachCaching? = nil,
        preferences: AICoachPreferencesProviding? = nil,
        availability: AICoachAvailabilityProviding? = nil
    ) {
        self.range = initialRange
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
            remainingFormat: "ai_coach.period_recap.allowance.nudge".localized,
            exhaustedText: "ai_coach.period_recap.allowance.nudge.exhausted".localized
        )
    }

    /// Raises `.periodRecap` from the unlock CTA on the `.gated` state.
    func unlock() {
        allowanceGate.presentPaywall()
    }

    /// Identity for the screen's `.task(id:)`, so a change of entitlement
    /// re-enters `load`.
    ///
    /// **This screen is the one place a gate is *stored* rather than derived.**
    /// `.gated` and `.offer` are written into `state` (they are steps in a flow —
    /// the screen waits for a tap), so unlike every other gate in the app they
    /// do not fix themselves when the entitlement changes. Left alone, a user who
    /// bought Pro from this very screen's paywall kept the lock *and* lost the
    /// CTA: `unlock()` asks `PaywallPresenter`, which correctly refuses to show
    /// a paywall to a Pro user, so the button became inert. Re-entry is what
    /// clears it — and for a now-unmetered user, `load` streams the recap they
    /// just paid for.
    ///
    /// Reading `isMetered` is what makes this live: it goes through the
    /// `@Observable` entitlement provider, so the view's `body` registers the
    /// dependency and SwiftUI restarts the task on its own
    /// (docs/pro-subscription.md §3c).
    var allowanceReloadKey: Bool { allowanceGate.isMetered }

    // MARK: - Public API

    /// Load from cache if available, otherwise stream fresh content.
    ///
    /// Navigation, not intent: a metered user lands on `.offer` rather than on
    /// a generation they did not ask for.
    func load(modelContext: ModelContext) async {
        streamTask?.cancel()
        state = .loading
        streamTask = Task { [weak self] in
            await self?.run(modelContext: modelContext, bypassCache: false, ticket: nil)
        }
    }

    /// Bypass cache and stream fresh content for the current range.
    ///
    /// The gate is asked **before** the cache is invalidated, and a refusal
    /// leaves the state untouched: the recap the user already spent an
    /// allowance on stays on screen and on disk behind the paywall (§7 Rule 4).
    func regenerate(modelContext: ModelContext) async {
        guard let ticket = allowanceGate.requestGeneration() else { return }
        streamTask?.cancel()
        let key = buildCacheKey(range: range, modelContext: modelContext)
        if let key { cache.invalidatePeriodRecap(key: key) }
        state = .loading
        streamTask = Task { [weak self, gate = allowanceGate] in
            guard let self else {
                gate.refund(ticket)
                return
            }
            await self.run(modelContext: modelContext, bypassCache: true, ticket: ticket)
        }
    }

    /// The explicit "generate it" tap on the `.offer` state — the only path
    /// that spends a metered user's monthly recap.
    func generateNow(modelContext: ModelContext) async {
        guard let ticket = allowanceGate.requestGeneration() else {
            state = .gated(buildHeadlineMetrics(range: range, modelContext: modelContext))
            return
        }
        streamTask?.cancel()
        state = .loading
        streamTask = Task { [weak self, gate = allowanceGate] in
            guard let self else {
                gate.refund(ticket)
                return
            }
            await self.run(modelContext: modelContext, bypassCache: false, ticket: ticket)
        }
    }

    /// Switch to a different range and reload.
    func setRange(_ newRange: PeriodRange, modelContext: ModelContext) async {
        guard newRange != range else { return }
        streamTask?.cancel()
        range = newRange
        state = .loading
        streamTask = Task { [weak self] in
            await self?.run(modelContext: modelContext, bypassCache: false, ticket: nil)
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
    }

#if DEBUG
    /// Test hook: awaits the in-flight generation so a test can assert on the
    /// terminal state (and on what the allowance was charged) instead of
    /// polling `Task.yield()`. The generation itself is fire-and-forget by
    /// design — the `.task` that starts it must be free to be cancelled
    /// independently — which is why this is a hook rather than an `await` in
    /// `load`.
    func waitForCurrentGeneration() async {
        await streamTask?.value
    }
#endif

    // MARK: - Core Pipeline

    /// - Parameter ticket: a generation the user already authorised
    ///   (`generateNow`, `regenerate`), or `nil` on the navigation path, where
    ///   the allowance is resolved at step 5 instead. Every exit that does not
    ///   produce a recap gives the unit back.
    private func run(
        modelContext: ModelContext,
        bypassCache: Bool,
        ticket: AICoachAllowanceGate.Ticket?
    ) async {
        var pending = ticket
        defer { if let pending { allowanceGate.refund(pending) } }

        // 1. Availability
        switch availability.state {
        case .deviceNotEligible, .appleIntelligenceNotEnabled:
            let metrics = buildHeadlineMetrics(range: range, modelContext: modelContext)
            state = .unavailable(metrics)
            return
        case .modelNotReady, .unknown:
            try? await Task.sleep(for: .seconds(2))
            await availability.refresh()
            if !availability.isAvailable {
                let metrics = buildHeadlineMetrics(range: range, modelContext: modelContext)
                state = .unavailable(metrics)
                return
            }
        case .available:
            break
        }

        // 2. Preferences
        let prefs = preferences
        guard prefs.isPeriodRecapEffectivelyEnabled else {
            let metrics = buildHeadlineMetrics(range: range, modelContext: modelContext)
            state = .unavailable(metrics)
            return
        }

        // 3. Insufficiency check — build input to determine session count
        let sampleInput = aggregator.buildInput(
            range: range,
            locale: Locale.current,
            modelContext: modelContext
        )
        if sampleInput.isInsufficient {
            state = .insufficient(sampleInput.headline)
            return
        }

        // 4. Cache hit
        if !bypassCache {
            let cacheKey = buildCacheKey(range: range, modelContext: modelContext)
            if let key = cacheKey,
               let cached = cache.loadPeriodRecap(key: key) {
                let fileDate = cacheFileDate(key: key) ?? Date()
                let metrics = buildHeadlineMetrics(range: range, modelContext: modelContext)
                state = .success(cached, isCached: true, generatedAt: fileDate, metrics: metrics)
                return
            }
        }

        // 5. The free monthly taster (P4). Everything above this line stays
        //    free: an unavailable device, a period too thin to narrate and —
        //    above all — a cached recap never reach the meter.
        guard let admitted = admitGeneration(
            preAuthorized: pending,
            // Step 3's metrics, not a second aggregation: `buildHeadlineMetrics`
            // fetches sessions and walks their exercise relationships on the
            // main actor, and `sampleInput.headline` is the same figure the
            // screen would show.
            metrics: sampleInput.headline
        ) else { return }
        pending = admitted

        // 6. Stream
        if await stream(
            range: range,
            modelContext: modelContext,
            headlineMetrics: sampleInput.headline
        ) {
            pending = nil
        }
    }

    /// Resolves the allowance for a generation about to start, or parks the
    /// screen on the offer / the gate and returns `nil`.
    ///
    /// The navigation path (`load`, `setRange`) deliberately never generates
    /// for a metered user. One free recap a month is a single, irreversible
    /// choice, and opening the screen — or tapping a range chip, or following
    /// the proactive month-boundary prompt — must not be the thing that spends
    /// it. An unmetered user is unaffected: they stream immediately, exactly as
    /// the screen did before monetization.
    private func admitGeneration(
        preAuthorized: AICoachAllowanceGate.Ticket?,
        metrics: HeadlineMetrics?
    ) -> AICoachAllowanceGate.Ticket? {
        if let preAuthorized { return preAuthorized }
        guard allowanceGate.isMetered else { return allowanceGate.requestGeneration() }

        if allowanceGate.isExhausted {
            allowanceGate.presentPaywallIfExhausted()
            state = .gated(metrics)
        } else {
            state = .offer(metrics)
        }
        return nil
    }

    // MARK: - Streaming

    /// - Returns: `true` only when a complete recap reached the screen and the
    ///   cache. The caller keeps the allowance unit on `true` and refunds it
    ///   otherwise — a cancelled or superseded stream surfaces nothing and
    ///   saves nothing, so it costs the user nothing.
    @discardableResult
    private func stream(
        range: PeriodRange,
        modelContext: ModelContext,
        headlineMetrics: HeadlineMetrics
    ) async -> Bool {
        let locale = Locale.current
        let capturedRange = range

        // Seed partial content with known headline metrics
        var partial = PartialContent()
        partial.headlineMetrics = headlineMetrics
        state = .streaming(partial)

        let start = ContinuousClock.now

        do {
            guard let responseStream = try await service.streamPeriodRecap(
                buildInput: {
                    self.aggregator.buildInput(
                        range: capturedRange,
                        locale: locale,
                        modelContext: modelContext
                    )
                },
                buildCompactInput: {
                    self.aggregator.buildCompactInput(
                        range: capturedRange,
                        locale: locale,
                        modelContext: modelContext
                    )
                }
            ) else {
                let metrics = buildHeadlineMetrics(range: capturedRange, modelContext: modelContext)
                state = .unavailable(metrics)
                return false
            }

            var finalOutput: PeriodRecapOutput?

            for try await snapshot in responseStream {
                guard !Task.isCancelled else { break }
                let p = snapshot.content
                partial.headline = p.headline ?? ""
                partial.trendsNarrative = p.trendsNarrative ?? ""
                // PartiallyGenerated wraps Optional fields in another Optional.
                // p.correlationHighlight is String?? — inner nil means "field not yet generated",
                // outer nil means schema returned null. Flatten both to String?.
                partial.correlationHighlight = p.correlationHighlight ?? nil
                partial.closingSentence = p.closingSentence ?? ""
                partial.headlineMetrics = headlineMetrics
                // Only update state if the range hasn't changed under us
                if self.range == capturedRange {
                    state = .streaming(partial)
                }
                // Track the last complete snapshot
                if let headline = p.headline,
                   let trends = p.trendsNarrative,
                   let closing = p.closingSentence {
                    let rawCorr: String? = p.correlationHighlight ?? nil
                    let corr = Self.isApologeticCorrelation(rawCorr) ? nil : rawCorr
                    finalOutput = PeriodRecapOutput(
                        headline: headline,
                        trendsNarrative: trends,
                        correlationHighlight: corr,
                        closingSentence: closing
                    )
                }
            }

            // If cancelled mid-stream, do not surface partial output.
            guard !Task.isCancelled else { return false }

            guard let output = finalOutput else {
                if self.range == capturedRange {
                    state = .error("ai_coach.period_recap.error.empty_output".localized)
                }
                return false
            }

            // Cache and surface result only if range hasn't changed
            var didDeliver = false
            if self.range == capturedRange {
                let key = buildCacheKey(range: capturedRange, modelContext: modelContext)
                if let key { cache.savePeriodRecap(key: key, output: output) }
                state = .success(output, isCached: false, generatedAt: Date(), metrics: headlineMetrics)
                didDeliver = true
            }

            let elapsed = ContinuousClock.now - start
            let ms = Int(Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15)
            AICoachTelemetry.recordGeneration(
                useCase: "period_recap",
                durationMs: ms,
                inputTokens: nil,
                outputTokens: nil,
                success: true
            )
            return didDeliver

        } catch let error as LanguageModelSession.GenerationError {
            let elapsed = ContinuousClock.now - start
            let ms = Int(Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15)

            switch error {
            case .guardrailViolation:
                logger.warning("period_recap guardrail violation — falling back silently")
                AICoachTelemetry.recordGeneration(useCase: "period_recap", durationMs: ms, inputTokens: nil, outputTokens: nil, success: false)
                let metrics = buildHeadlineMetrics(range: capturedRange, modelContext: modelContext)
                if self.range == capturedRange { state = .unavailable(metrics) }
            default:
                logger.error("period_recap error: \(error.localizedDescription, privacy: .public)")
                AICoachTelemetry.recordError(useCase: "period_recap", errorTypeName: String(describing: type(of: error)))
                if self.range == capturedRange { state = .error(error.localizedDescription) }
            }

        } catch {
            let elapsed = ContinuousClock.now - start
            let ms = Int(Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15)
            logger.error("period_recap unexpected error: \(error.localizedDescription, privacy: .public)")
            AICoachTelemetry.recordError(useCase: "period_recap", errorTypeName: String(describing: type(of: error)))
            AICoachTelemetry.recordGeneration(useCase: "period_recap", durationMs: ms, inputTokens: nil, outputTokens: nil, success: false)
            if self.range == capturedRange { state = .error(error.localizedDescription) }
        }

        return false
    }

    // MARK: - Cache Key

    /// Builds the cache key: `"\(range.cacheKey)|\(rangeStartISO)|\(lastWorkoutISO)"`.
    private func buildCacheKey(range: PeriodRange, modelContext: ModelContext) -> String? {
        let interval = range.dateInterval()
        guard let lastWorkout = aggregator.mostRecentSessionStart(in: interval, modelContext: modelContext) else {
            return nil
        }
        return "\(range.cacheKey)|\(isoFmt.string(from: interval.start))|\(isoFmt.string(from: lastWorkout))"
    }

    /// Approximates the cache file modification date by checking the file system.
    private func cacheFileDate(key: String) -> Date? {
        let safe = key.components(
            separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "-_")).inverted
        ).joined(separator: "_")
        let fm = FileManager.default
        guard let support = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return nil }
        let url = support
            .appending(path: "AICoachCache", directoryHint: .isDirectory)
            .appending(path: "period_recap_\(safe).json", directoryHint: .notDirectory)
        return (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    // MARK: - Apologetic correlation guard

    /// Returns `true` if `text` is most likely an "apologetic empty correlation" rather
    /// than a real finding (e.g. "There are no notable correlations…"). The prompt's
    /// pattern statements are pre-written findings the model reproduces verbatim, so
    /// only explicit "nothing found" phrasing needs to be caught — a subject-matching
    /// heuristic would misclassify the (short, exercise-name-free) real statements.
    private static func isApologeticCorrelation(_ text: String?) -> Bool {
        guard let text, !text.isEmpty else { return true }
        let lower = text.lowercased()
        let markers = [
            "no correlation", "no notable", "no pattern", "not enough data",
            "keine korrelation", "keine zusammenhänge", "keine muster",
            "keine auffälligkeiten", "nicht genug daten"
        ]
        return markers.contains { lower.contains($0) }
    }

    // MARK: - Quick Headline (no full aggregation)

    private func buildHeadlineMetrics(range: PeriodRange, modelContext: ModelContext) -> HeadlineMetrics? {
        aggregator.headlineMetrics(in: range.dateInterval(), modelContext: modelContext)
    }
}
