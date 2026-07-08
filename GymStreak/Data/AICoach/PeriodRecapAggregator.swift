//
//  PeriodRecapAggregator.swift
//  GymStreak
//

import Foundation
import SwiftData
import os

/// Builds a `PeriodRecapInput` from SwiftData history for the AI Coach period recap.
///
/// `PeriodRange` itself lives in `Domain/Models/AICoach/PeriodRange.swift` — it's
/// consumed by the Domain-layer `PeriodRecapDestination`, so it can't live here.
struct PeriodRecapAggregator {

    private static let logger = Logger(subsystem: "com.gymstreak", category: "PeriodRecapAggregator")

    // MARK: - Epley helper

    private static func epley(weight: Double, reps: Int) -> Double {
        weight * (1.0 + Double(reps) / 30.0)
    }

    // MARK: - Public API

    func buildInput(
        range: PeriodRange,
        locale: Locale,
        modelContext: ModelContext,
        now: Date = Date()
    ) -> PeriodRecapInput {
        let interval = range.dateInterval(now: now)
        let sessions = fetchSessions(in: interval, modelContext: modelContext)

        let headline = buildHeadline(from: sessions)
        let consistency = buildConsistency(sessions: sessions, interval: interval, now: now)
        let isInsufficient = sessions.count < 3

        let trends: [TrendFinding]
        let correlations: [CorrelationFinding]
        var recommendationFact: String?

        if isInsufficient {
            trends = []
            correlations = []
            recommendationFact = nil
        } else {
            let liveExercises = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
            trends = buildTrends(sessions: sessions, liveExercises: liveExercises, maxCount: 5)
            correlations = buildCorrelations(sessions: sessions, locale: locale, now: now)
            recommendationFact = buildRecommendation(
                sessions: sessions,
                trends: trends,
                consistency: consistency,
                now: now
            )
        }

        return PeriodRecapInput(
            locale: locale.identifier,
            periodLabel: range.label(locale: locale, now: now),
            headline: headline,
            consistency: consistency,
            trends: trends,
            correlations: correlations,
            recommendationFact: recommendationFact,
            isInsufficient: isInsufficient
        )
    }

    /// Compact fallback: limits trends to 3, correlations to 1.
    /// The FM bridge agent falls back to this when the full input exceeds token budget.
    func buildCompactInput(
        range: PeriodRange,
        locale: Locale,
        modelContext: ModelContext,
        now: Date = Date()
    ) -> PeriodRecapInput {
        let full = buildInput(range: range, locale: locale, modelContext: modelContext, now: now)
        return PeriodRecapInput(
            locale: full.locale,
            periodLabel: full.periodLabel,
            headline: full.headline,
            consistency: full.consistency,
            trends: Array(full.trends.prefix(3)),
            correlations: Array(full.correlations.prefix(1)),
            recommendationFact: full.recommendationFact,
            isInsufficient: full.isInsufficient
        )
    }

    // MARK: - Fetch

    private func fetchSessions(in interval: DateInterval, modelContext: ModelContext) -> [WorkoutSession] {
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.startTime >= start && session.startTime < end && session.endTime != nil
            },
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Cache Key / Quick-Lookup Queries
    //
    // These support `PeriodRecapViewModel`'s cache-key building and quick headline
    // display — kept separate from `buildInput` because they're needed even when
    // the surface is unavailable or before full aggregation is warranted.

    /// Returns the most recent completed session's start time within `interval`,
    /// used to build the period-recap cache key. Returns `nil` when there are no
    /// completed sessions (or the fetch itself fails).
    func mostRecentSessionStart(in interval: DateInterval, modelContext: ModelContext) -> Date? {
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.startTime >= start && session.startTime < end && session.endTime != nil
            },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        guard let sessions = try? modelContext.fetch(descriptor), !sessions.isEmpty else { return nil }
        return sessions[0].startTime
    }

    /// Builds headline metrics for sessions within `interval`, independent of the
    /// full trends/correlations aggregation. Returns `nil` only if the fetch fails.
    func headlineMetrics(in interval: DateInterval, modelContext: ModelContext) -> HeadlineMetrics? {
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.startTime >= start && session.startTime < end && session.endTime != nil
            }
        )
        guard let sessions = try? modelContext.fetch(descriptor) else { return nil }
        return buildHeadline(from: sessions)
    }

    // MARK: - Headline

    private func buildHeadline(from sessions: [WorkoutSession]) -> HeadlineMetrics {
        let totalVolume = sessions.reduce(0.0) { $0 + $1.totalVolume }
        let avgDuration = sessions.isEmpty ? 0 : Int(sessions.reduce(0.0) { $0 + $1.duration } / Double(sessions.count) / 60)
        let distinctExercises = Set(
            sessions.flatMap { $0.workoutExercisesList.map(\.stableKey) }
        ).count

        return HeadlineMetrics(
            totalSessions: sessions.count,
            totalVolumeKg: totalVolume,
            averageSessionMinutes: avgDuration,
            distinctExercises: distinctExercises
        )
    }

    // MARK: - Consistency

    /// Regularity metrics: weeks covered vs. weeks trained, average weekly
    /// frequency, and the longest gap between two sessions. For running periods
    /// ("this month") only the elapsed part counts, so mid-period recaps aren't
    /// flagged irregular for weeks that haven't happened yet.
    private func buildConsistency(
        sessions: [WorkoutSession],
        interval: DateInterval,
        now: Date
    ) -> ConsistencyMetrics {
        let calendar = Calendar(identifier: .iso8601)
        let effectiveEnd = min(interval.end, now)
        let days = max(1, calendar.dateComponents([.day], from: interval.start, to: effectiveEnd).day ?? 7)
        let totalWeeks = max(1, Int((Double(days) / 7.0).rounded(.up)))

        let weekKeyFmt = DateFormatter()
        weekKeyFmt.calendar = calendar
        weekKeyFmt.dateFormat = "YYYY-ww"
        let trainedWeeks = min(Set(sessions.map { weekKeyFmt.string(from: $0.startTime) }).count, totalWeeks)

        let starts = sessions.map(\.startTime).sorted()
        var longestGapDays = 0
        for i in 1..<max(1, starts.count) {
            let gap = calendar.dateComponents([.day], from: starts[i - 1], to: starts[i]).day ?? 0
            longestGapDays = max(longestGapDays, gap)
        }

        let average = totalWeeks > 0 ? Double(sessions.count) / Double(totalWeeks) : 0
        let isIrregular = trainedWeeks < totalWeeks || longestGapDays >= 9

        return ConsistencyMetrics(
            totalWeeks: totalWeeks,
            trainedWeeks: trainedWeeks,
            averageSessionsPerWeek: (average * 10).rounded() / 10,
            longestGapDays: longestGapDays,
            isIrregular: isIrregular
        )
    }

    // MARK: - Recommendation

    /// Resolves at most one actionable recommendation, only when stagnation
    /// demonstrably coincides with irregular training. English fact string —
    /// the model translates and phrases it.
    private func buildRecommendation(
        sessions: [WorkoutSession],
        trends: [TrendFinding],
        consistency: ConsistencyMetrics,
        now: Date
    ) -> String? {
        let hasImprovement = trends.contains { $0.direction == "improved" }
        let hasStagnation = trends.contains { $0.direction == "plateaued" || $0.direction == "regressed" }

        if let adherence = adherenceDipsVsRegressionCorrelation(sessions: sessions, now: now),
           adherence.lowAdherencePrecededRegression {
            return "performance dips followed weeks with fewer sessions — keeping the frequency steady at about \(String(format: "%.1f", consistency.averageSessionsPerWeek)) sessions per week should help"
        }
        if consistency.isIrregular && hasStagnation && !hasImprovement {
            return "progress stalled while training was irregular (longest gap \(consistency.longestGapDays) days) — more evenly spaced sessions would likely get progress moving again"
        }
        return nil
    }

    // MARK: - Trends

    private func buildTrends(
        sessions: [WorkoutSession],
        liveExercises: [Exercise],
        maxCount: Int
    ) -> [TrendFinding] {
        // Build lookup tables mirroring FortschrittAggregator's resolveLive pattern
        var liveById: [UUID: Exercise] = [:]
        var liveByName: [String: [Exercise]] = [:]
        for ex in liveExercises {
            liveById[ex.id] = ex
            liveByName[ex.name.lowercased(), default: []].append(ex)
        }

        // Accumulate ordered estimated-1RM data points per live exercise
        struct DataPoint { let date: Date; let est1RM: Double }
        var dataByExercise: [UUID: (name: String, points: [DataPoint])] = [:]

        for session in sessions {
            for we in session.workoutExercisesList {
                guard let live = Self.resolveLive(we, byId: liveById, byName: liveByName) else { continue }
                let usePlanned = we.progressiveOverloadApplied
                let completed = we.setsList.filter(\.isCompleted)
                guard !completed.isEmpty else { continue }

                var bestEst: Double = 0
                for set in completed {
                    let w = usePlanned ? set.plannedWeight : set.actualWeight
                    let r = usePlanned ? set.plannedReps : set.actualReps
                    guard w > 0, r > 0 else { continue }
                    bestEst = max(bestEst, Self.epley(weight: w, reps: r))
                }
                guard bestEst > 0 else { continue }

                var entry = dataByExercise[live.id] ?? (live.name, [])
                entry.points.append(DataPoint(date: session.startTime, est1RM: bestEst))
                dataByExercise[live.id] = entry
            }
        }

        // Filter to exercises with >= 2 sessions in the period; sort by frequency desc
        let qualified = dataByExercise
            .filter { $0.value.points.count >= 2 }
            .sorted { $0.value.points.count > $1.value.points.count }
            .prefix(8)

        // Linear regression & classification per exercise
        struct TrendCandidate {
            let name: String
            let direction: String
            let magnitude: String
            let absSlope: Double
        }

        let slopeThreshold = 0.5 // kg/session threshold to be "improving" or "regressing"

        var candidates: [TrendCandidate] = []
        for (_, data) in qualified {
            let points = data.points.sorted { $0.date < $1.date }
            let slope = Self.linearRegressionSlope(points.map(\.est1RM))
            let direction: String
            if slope >= slopeThreshold {
                direction = "improved"
            } else if slope <= -slopeThreshold {
                direction = "regressed"
            } else {
                direction = "plateaued"
            }

            let deltaKg = (points.last?.est1RM ?? 0) - (points.first?.est1RM ?? 0)
            let sign = deltaKg >= 0 ? "+" : ""
            let magnitude = "\(sign)\(String(format: "%.1f", deltaKg)) kg"

            candidates.append(TrendCandidate(
                name: data.name,
                direction: direction,
                magnitude: magnitude,
                absSlope: abs(slope)
            ))
        }

        // Return top N sorted by absolute slope (most dramatic first)
        return candidates
            .sorted { $0.absSlope > $1.absSlope }
            .prefix(maxCount)
            .map { TrendFinding(subject: $0.name, direction: $0.direction, magnitude: $0.magnitude) }
    }

    // MARK: - Correlations

    private func buildCorrelations(
        sessions: [WorkoutSession],
        locale: Locale,
        now: Date
    ) -> [CorrelationFinding] {
        let isGerman = locale.identifier.hasPrefix("de")
        var findings: [(statement: String, effectSize: Double)] = []

        // 1. Frequency vs progression: Pearson on weekly session count vs weekly avg est-1RM
        if let freqCorr = frequencyVsProgressionCorrelation(sessions: sessions, now: now) {
            if abs(freqCorr.r) > 0.5 && freqCorr.weekCount >= 4 {
                let statement: String
                if freqCorr.r > 0 {
                    statement = isGerman
                        ? "In Wochen mit mehr Einheiten war dein Fortschritt tendenziell stärker."
                        : "Weeks with more sessions tended to show stronger progress."
                } else {
                    statement = isGerman
                        ? "In Wochen mit weniger Einheiten war dein Fortschritt stabiler."
                        : "Weeks with fewer sessions tended to have more consistent progress."
                }
                findings.append((statement, abs(freqCorr.r)))
            }
        }

        // 2. Adherence dips vs regression weeks
        if let adherenceCorr = adherenceDipsVsRegressionCorrelation(sessions: sessions, now: now) {
            if adherenceCorr.regressionWeeks > 0 && adherenceCorr.lowAdherencePrecededRegression {
                let statement: String
                statement = isGerman
                    ? "Auf Wochen mit weniger Training folgten häufiger Leistungsrückgänge."
                    : "Weeks with lower training frequency were often followed by performance dips."
                findings.append((statement, adherenceCorr.effectSize))
            }
        }

        return findings
            .sorted { $0.effectSize > $1.effectSize }
            .prefix(2)
            .map { CorrelationFinding(statement: $0.statement) }
    }

    // MARK: - Correlation Helpers

    private struct FrequencyCorrelationResult {
        let r: Double
        let weekCount: Int
    }

    private func frequencyVsProgressionCorrelation(
        sessions: [WorkoutSession],
        now: Date
    ) -> FrequencyCorrelationResult? {
        // Bucket sessions by ISO week key
        let calendar = Calendar(identifier: .iso8601)
        let weekKeyFmt = DateFormatter()
        weekKeyFmt.calendar = calendar
        weekKeyFmt.dateFormat = "YYYY-ww"

        var countByWeek: [String: Int] = [:]
        var allEst1RMByWeek: [String: [Double]] = [:]

        for session in sessions {
            let key = weekKeyFmt.string(from: session.startTime)
            countByWeek[key, default: 0] += 1

            for exercise in session.workoutExercisesList {
                let usePlanned = exercise.progressiveOverloadApplied
                for set in exercise.setsList where set.isCompleted {
                    let w = usePlanned ? set.plannedWeight : set.actualWeight
                    let r = usePlanned ? set.plannedReps : set.actualReps
                    guard w > 0, r > 0 else { continue }
                    let est = Self.epley(weight: w, reps: r)
                    allEst1RMByWeek[key, default: []].append(est)
                }
            }
        }

        let weeks = Array(countByWeek.keys)
        guard weeks.count >= 4 else { return nil }

        let x = weeks.compactMap { countByWeek[$0].map(Double.init) }
        let y = weeks.compactMap { allEst1RMByWeek[$0].flatMap { $0.isEmpty ? nil : $0.reduce(0, +) / Double($0.count) } }
        guard x.count == weeks.count, y.count == weeks.count else { return nil }

        let r = Self.pearsonCorrelation(x: x, y: y)
        return FrequencyCorrelationResult(r: r, weekCount: weeks.count)
    }

    private struct AdherenceCorrelationResult {
        let regressionWeeks: Int
        let lowAdherencePrecededRegression: Bool
        let effectSize: Double
    }

    private func adherenceDipsVsRegressionCorrelation(
        sessions: [WorkoutSession],
        now: Date
    ) -> AdherenceCorrelationResult? {
        let calendar = Calendar(identifier: .iso8601)
        let weekKeyFmt = DateFormatter()
        weekKeyFmt.calendar = calendar
        weekKeyFmt.dateFormat = "YYYY-ww"

        var countByWeek: [String: Int] = [:]
        var avgEst1RMByWeek: [String: Double] = [:]

        for session in sessions {
            let key = weekKeyFmt.string(from: session.startTime)
            countByWeek[key, default: 0] += 1

            var est1RMs: [Double] = []
            for exercise in session.workoutExercisesList {
                let usePlanned = exercise.progressiveOverloadApplied
                for set in exercise.setsList where set.isCompleted {
                    let w = usePlanned ? set.plannedWeight : set.actualWeight
                    let r = usePlanned ? set.plannedReps : set.actualReps
                    guard w > 0, r > 0 else { continue }
                    est1RMs.append(Self.epley(weight: w, reps: r))
                }
            }
            if !est1RMs.isEmpty {
                let current = avgEst1RMByWeek[key] ?? 0
                avgEst1RMByWeek[key] = max(current, est1RMs.reduce(0, +) / Double(est1RMs.count))
            }
        }

        let sortedWeeks = countByWeek.keys.sorted()
        guard sortedWeeks.count >= 4 else { return nil }

        let avgCount = Double(countByWeek.values.reduce(0, +)) / Double(countByWeek.count)
        var regressionWeeks = 0
        var lowAdherenceFollowedByRegression = 0

        for i in 1..<sortedWeeks.count {
            let prevWeek = sortedWeeks[i - 1]
            let thisWeek = sortedWeeks[i]
            let prevCount = Double(countByWeek[prevWeek] ?? 0)
            let prevEst = avgEst1RMByWeek[prevWeek] ?? 0
            let thisEst = avgEst1RMByWeek[thisWeek] ?? 0

            if thisEst < prevEst {
                regressionWeeks += 1
                if prevCount < avgCount {
                    lowAdherenceFollowedByRegression += 1
                }
            }
        }

        guard regressionWeeks > 0 else { return nil }
        let ratio = Double(lowAdherenceFollowedByRegression) / Double(regressionWeeks)
        return AdherenceCorrelationResult(
            regressionWeeks: regressionWeeks,
            lowAdherencePrecededRegression: ratio > 0.5,
            effectSize: ratio
        )
    }

    // MARK: - Statistics Helpers

    /// Least-squares slope over equally-spaced y-values.
    private static func linearRegressionSlope(_ values: [Double]) -> Double {
        let n = Double(values.count)
        guard n >= 2 else { return 0 }
        let x = (0..<Int(n)).map(Double.init)
        let meanX = x.reduce(0, +) / n
        let meanY = values.reduce(0, +) / n
        let numerator = zip(x, values).reduce(0.0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let denominator = x.reduce(0.0) { $0 + ($1 - meanX) * ($1 - meanX) }
        return denominator == 0 ? 0 : numerator / denominator
    }

    /// Pearson correlation coefficient between two equal-length arrays.
    private static func pearsonCorrelation(x: [Double], y: [Double]) -> Double {
        let n = Double(x.count)
        guard n >= 2, x.count == y.count else { return 0 }
        let meanX = x.reduce(0, +) / n
        let meanY = y.reduce(0, +) / n
        let numerator = zip(x, y).reduce(0.0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let sdX = sqrt(x.reduce(0.0) { $0 + pow($1 - meanX, 2) } / n)
        let sdY = sqrt(y.reduce(0.0) { $0 + pow($1 - meanY, 2) } / n)
        guard sdX > 0, sdY > 0 else { return 0 }
        return numerator / (n * sdX * sdY)
    }

    /// Replicates `FortschrittAggregator.resolveLive` — resolves a `WorkoutExercise` to its
    /// live library entry, preferring `exerciseId`, falling back to unique-name match.
    private static func resolveLive(
        _ we: WorkoutExercise,
        byId: [UUID: Exercise],
        byName: [String: [Exercise]]
    ) -> Exercise? {
        if let id = we.exerciseId, let live = byId[id] { return live }
        let candidates = byName[we.exerciseName.lowercased()] ?? []
        return candidates.count == 1 ? candidates[0] : nil
    }
}
