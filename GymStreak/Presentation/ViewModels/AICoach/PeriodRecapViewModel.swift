//
//  PeriodRecapViewModel.swift
//  GymStreak
//
//  Orchestrates AI period recap generation: cache lookup, streaming,
//  range switching, and graceful degradation.
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
    init(
        initialRange: PeriodRange,
        service: AICoachServicing? = nil,
        cache: AICoachCaching? = nil,
        preferences: AICoachPreferencesProviding? = nil,
        availability: AICoachAvailabilityProviding? = nil
    ) {
        self.range = initialRange
        self.service = service ?? AICoachService.shared
        self.cache = cache ?? AICoachCache.shared
        self.preferences = preferences ?? AICoachPreferences.shared
        self.availability = availability ?? AICoachAvailability.shared
    }

    // MARK: - Public API

    /// Load from cache if available, otherwise stream fresh content.
    func load(modelContext: ModelContext) async {
        streamTask?.cancel()
        state = .loading
        streamTask = Task { [weak self] in
            await self?.run(modelContext: modelContext, bypassCache: false)
        }
    }

    /// Bypass cache and stream fresh content for the current range.
    func regenerate(modelContext: ModelContext) async {
        streamTask?.cancel()
        let key = buildCacheKey(range: range, modelContext: modelContext)
        if let key { cache.invalidatePeriodRecap(key: key) }
        state = .loading
        streamTask = Task { [weak self] in
            await self?.run(modelContext: modelContext, bypassCache: true)
        }
    }

    /// Switch to a different range and reload.
    func setRange(_ newRange: PeriodRange, modelContext: ModelContext) async {
        guard newRange != range else { return }
        streamTask?.cancel()
        range = newRange
        state = .loading
        streamTask = Task { [weak self] in
            await self?.run(modelContext: modelContext, bypassCache: false)
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
    }

    // MARK: - Core Pipeline

    private func run(modelContext: ModelContext, bypassCache: Bool) async {
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

        // 5. Stream
        await stream(
            range: range,
            modelContext: modelContext,
            headlineMetrics: sampleInput.headline
        )
    }

    // MARK: - Streaming

    private func stream(
        range: PeriodRange,
        modelContext: ModelContext,
        headlineMetrics: HeadlineMetrics
    ) async {
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
                return
            }

            var finalOutput: PeriodRecapOutput?
            let knownSubjects = buildKnownSubjects(headlineMetrics: headlineMetrics, modelContext: modelContext, range: capturedRange)

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
                    let corr = Self.isApologeticCorrelation(rawCorr, knownSubjects: knownSubjects) ? nil : rawCorr
                    finalOutput = PeriodRecapOutput(
                        headline: headline,
                        trendsNarrative: trends,
                        correlationHighlight: corr,
                        closingSentence: closing
                    )
                }
            }

            // If cancelled mid-stream, do not surface partial output.
            guard !Task.isCancelled else { return }

            guard let output = finalOutput else {
                if self.range == capturedRange {
                    state = .error("ai_coach.period_recap.error.empty_output".localized)
                }
                return
            }

            // Cache and surface result only if range hasn't changed
            if self.range == capturedRange {
                let key = buildCacheKey(range: capturedRange, modelContext: modelContext)
                if let key { cache.savePeriodRecap(key: key, output: output) }
                state = .success(output, isCached: false, generatedAt: Date(), metrics: headlineMetrics)
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
    /// than a real finding (e.g. "There are no notable correlations…").
    /// Heuristic: short text that contains none of the known exercise/muscle subjects.
    private static func isApologeticCorrelation(_ text: String?, knownSubjects: [String]) -> Bool {
        guard let text, !text.isEmpty else { return true }
        if text.count > 120 { return false } // long enough to be a real finding
        let lower = text.lowercased()
        return !knownSubjects.contains(where: { lower.contains($0.lowercased()) })
    }

    /// Builds the list of known subjects (exercise + muscle group names) from session data.
    /// Used as the reference set for the apologetic-correlation heuristic.
    private func buildKnownSubjects(headlineMetrics: HeadlineMetrics, modelContext: ModelContext, range: PeriodRange) -> [String] {
        aggregator.knownSubjects(in: range.dateInterval(), modelContext: modelContext)
    }

    // MARK: - Quick Headline (no full aggregation)

    private func buildHeadlineMetrics(range: PeriodRange, modelContext: ModelContext) -> HeadlineMetrics? {
        aggregator.headlineMetrics(in: range.dateInterval(), modelContext: modelContext)
    }
}
