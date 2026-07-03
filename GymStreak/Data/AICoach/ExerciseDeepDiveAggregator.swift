//
//  ExerciseDeepDiveAggregator.swift
//  GymStreak
//

import Foundation
import SwiftData
import os

/// Builds an `ExerciseDeepDiveInput` from all historical data for a single exercise.
/// Returns `nil` when there is insufficient history (fewer than 4 completed sets total).
struct ExerciseDeepDiveAggregator {

    private static let logger = Logger(subsystem: "com.gymstreak", category: "ExerciseDeepDiveAggregator")

    // MARK: - Epley

    private static func epley(weight: Double, reps: Int) -> Double {
        weight * (1.0 + Double(reps) / 30.0)  
    }

    // MARK: - Public API

    /// Builds the AI Coach deep-dive input for a single exercise.
    /// - Parameters:
    ///   - exercise: The live `Exercise` to analyze.
    ///   - locale: User's locale (for month label formatting).
    ///   - modelContext: SwiftData context for history queries.
    ///   - now: Injection point for current date (injectable for tests).
    /// - Returns: `nil` if the exercise has fewer than 4 completed sets across all history.
    func buildInput(
        exercise: Exercise,
        locale: Locale,
        modelContext: ModelContext,
        now: Date = Date()
    ) -> ExerciseDeepDiveInput? {
        let sessions = fetchSessions(exercise: exercise, modelContext: modelContext)
        let dataPoints = buildDataPoints(exercise: exercise, sessions: sessions)

        // Insufficient data guard: require at least 4 completed sets
        let totalSets = dataPoints.reduce(0) { $0 + $1.setCount }
        guard totalSets >= 4, dataPoints.count >= 2 else { return nil }

        let sortedPoints = dataPoints.sorted { $0.date < $1.date }
        guard let first = sortedPoints.first, let last = sortedPoints.last else { return nil }

        let firstEst = first.bestEst1RM
        let lastEst = last.bestEst1RM
        let deltaKg = lastEst - firstEst
        let percentChange = firstEst > 0 ? Int((deltaKg / firstEst * 100).rounded()) : 0

        let peak = findPeak(points: sortedPoints, locale: locale)
        let weeklyBuckets = buildWeeklyBuckets(points: sortedPoints)
        let strongestSegment = findStrongestSegment(buckets: weeklyBuckets, locale: locale, now: now)
        let currentSegment = buildCurrentSegment(buckets: weeklyBuckets, locale: locale, now: now)

        let historyRange = buildHistoryRange(first: first.date, last: last.date)

        return ExerciseDeepDiveInput(
            locale: locale.identifier,
            exerciseName: exercise.name,
            totalSessions: sortedPoints.count,
            historyRange: historyRange,
            overallProgression: ProgressionSummary(
                estimatedOneRMDeltaKg: deltaKg,
                percentChange: percentChange
            ),
            peak: peak,
            strongestSegment: strongestSegment,
            currentSegment: currentSegment
        )
    }

    // MARK: - Data Fetch

    private func fetchSessions(exercise: Exercise, modelContext: ModelContext) -> [WorkoutSession] {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.endTime != nil
            },
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Cache Key Query

    /// Returns the most recent session date containing a completed set matching
    /// `exerciseId` (or a legacy entry with no stored `exerciseId`), used by
    /// `ExerciseDeepDiveViewModel` to build its cache key. Returns `nil` when no
    /// matching completed set is found.
    func lastCompletedSetTimestamp(exerciseId: UUID, modelContext: ModelContext) -> Date? {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endTime != nil },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        guard let sessions = try? modelContext.fetch(descriptor) else { return nil }

        var latestTimestamp: Date?
        for session in sessions {
            for we in session.workoutExercisesList {
                guard we.exerciseId == exerciseId || we.exerciseId == nil else { continue }
                let completedSets = we.setsList.filter(\.isCompleted)
                if !completedSets.isEmpty {
                    latestTimestamp = session.startTime
                    break
                }
            }
            if latestTimestamp != nil { break }
        }
        return latestTimestamp
    }

    // MARK: - Per-Session Data Points

    private struct SessionDataPoint {
        let date: Date
        let bestEst1RM: Double
        let bestWeight: Double
        let bestReps: Int
        let setCount: Int
    }

    private func buildDataPoints(exercise: Exercise, sessions: [WorkoutSession]) -> [SessionDataPoint] {
        // Resolve by exerciseId (primary) or unique name fallback, matching ExerciseProgressService.matches.
        let exerciseId = exercise.id
        let exerciseName = exercise.name.lowercased()

        var points: [SessionDataPoint] = []

        for session in sessions {
            var bestEst: Double = 0
            var bestW: Double = 0
            var bestR: Int = 0
            var setCount = 0

            for we in session.workoutExercisesList {
                guard Self.matchesExercise(we, exerciseId: exerciseId, nameLower: exerciseName) else { continue }
                let usePlanned = we.progressiveOverloadApplied
                let completed = we.setsList.filter(\.isCompleted)
                setCount += completed.count

                for set in completed {
                    let w = usePlanned ? set.plannedWeight : set.actualWeight
                    let r = usePlanned ? set.plannedReps : set.actualReps
                    guard w > 0, r > 0 else { continue }
                    let est = Self.epley(weight: w, reps: r)
                    if est > bestEst {
                        bestEst = est
                        bestW = w
                        bestR = r
                    }
                }
            }

            guard bestEst > 0 else { continue }
            points.append(SessionDataPoint(
                date: session.startTime,
                bestEst1RM: bestEst,
                bestWeight: bestW,
                bestReps: bestR,
                setCount: setCount
            ))
        }

        return points
    }

    /// Matches a `WorkoutExercise` to the target exercise by id (primary) or lowercased name (fallback).
    private static func matchesExercise(
        _ we: WorkoutExercise,
        exerciseId: UUID,
        nameLower: String
    ) -> Bool {
        if we.exerciseId == exerciseId { return true }
        // Legacy name fallback only if no exerciseId stored on the workout entry
        if we.exerciseId == nil, we.exerciseName.lowercased() == nameLower { return true }
        return false
    }

    // MARK: - Peak

    private func findPeak(points: [SessionDataPoint], locale: Locale) -> PerformancePoint {
        // Match the chart's "PR" definition: highest raw weight lifted, ties broken by reps.
        // Do NOT use est-1RM as the primary sort key — it can select a lower raw weight
        // (e.g. 85 kg × 6 → est-1RM 102 beats 87 kg × 5 → est-1RM 101.5), which contradicts
        // the PR marker the user sees on the chart.
        let peak = points.max { a, b in
            if a.bestWeight != b.bestWeight { return a.bestWeight < b.bestWeight }
            return a.bestReps < b.bestReps
        } ?? points[0]
        return PerformancePoint(
            weightKg: peak.bestWeight,
            reps: peak.bestReps,
            estimatedOneRMKg: peak.bestEst1RM,
            monthLabel: Self.monthLabel(for: peak.date, locale: locale)
        )
    }

    // MARK: - Weekly Buckets

    private struct WeeklyBucket {
        let weekStart: Date
        let avgEst1RM: Double
        let sessionCount: Int
    }

    private func buildWeeklyBuckets(points: [SessionDataPoint]) -> [WeeklyBucket] {
        let calendar = Calendar(identifier: .iso8601)
        let grouped = Dictionary(grouping: points) { point -> Date in
            calendar.dateInterval(of: .weekOfYear, for: point.date)?.start ?? point.date
        }
        return grouped
            .map { weekStart, pts in
                let avg = pts.reduce(0.0) { $0 + $1.bestEst1RM } / Double(pts.count)
                return WeeklyBucket(weekStart: weekStart, avgEst1RM: avg, sessionCount: pts.count)
            }
            .sorted { $0.weekStart < $1.weekStart }
    }

    // MARK: - Strongest Segment

    /// Finds the contiguous sub-range of weekly buckets with the largest positive slope,
    /// requiring at least 4 weeks for a meaningful segment.
    private func findStrongestSegment(
        buckets: [WeeklyBucket],
        locale: Locale,
        now: Date
    ) -> ProgressionSegment {
        guard buckets.count >= 4 else {
            return buildSegmentFrom(buckets: buckets, locale: locale)
        }

        var bestStart = 0
        var bestEnd = buckets.count - 1
        var bestDelta: Double = 0

        // Sliding window: try all sub-ranges of length >= 4.
        // start is bounded to buckets.count - 4 so that (start + 3) is always a valid index.
        let maxStart = buckets.count - 4
        for start in 0...maxStart {
            for end in (start + 3)..<buckets.count {
                let slice = Array(buckets[start...end])
                let delta = (slice.last?.avgEst1RM ?? 0) - (slice.first?.avgEst1RM ?? 0)
                if delta > bestDelta {
                    bestDelta = delta
                    bestStart = start
                    bestEnd = end
                }
            }
        }

        let bestSlice = Array(buckets[bestStart...bestEnd])
        return buildSegmentFrom(buckets: bestSlice, locale: locale)
    }

    // MARK: - Current Segment

    /// Builds a segment from the last 4–8 weekly buckets.
    private func buildCurrentSegment(
        buckets: [WeeklyBucket],
        locale: Locale,
        now: Date
    ) -> ProgressionSegment {
        let windowSize = min(8, max(4, buckets.count))
        let slice = Array(buckets.suffix(windowSize))
        return buildSegmentFrom(buckets: slice, locale: locale)
    }

    // MARK: - Segment Builder

    private func buildSegmentFrom(buckets: [WeeklyBucket], locale: Locale) -> ProgressionSegment {
        guard !buckets.isEmpty else {
            return ProgressionSegment(
                classification: "plateau",
                range: "",
                avgSessionsPerWeek: 0,
                magnitude: "stable"
            )
        }

        let firstEst = buckets.first?.avgEst1RM ?? 0
        let lastEst = buckets.last?.avgEst1RM ?? 0
        let delta = lastEst - firstEst
        let slopeThreshold = 0.5

        let classification: String
        if delta >= slopeThreshold {
            classification = "improving"
        } else if delta <= -slopeThreshold {
            classification = "regressing"
        } else {
            classification = "plateau"
        }

        let rangeStr: String
        if let first = buckets.first?.weekStart, let last = buckets.last?.weekStart {
            let fmt = DateFormatter()
            fmt.locale = locale
            fmt.setLocalizedDateFormatFromTemplate("MMMM yyyy")
            let startLabel = fmt.string(from: first)
            let endLabel = fmt.string(from: last)
            rangeStr = startLabel == endLabel ? startLabel : "\(startLabel) – \(endLabel)"
        } else {
            rangeStr = ""
        }

        let totalSessions = buckets.reduce(0) { $0 + $1.sessionCount }
        let avgPerWeek = buckets.isEmpty ? 0.0 : Double(totalSessions) / Double(buckets.count)

        let sign = delta >= 0 ? "+" : ""
        let magnitude = abs(delta) < 0.5
            ? "stable"
            : "\(sign)\(String(format: "%.1f", delta))kg est. 1RM"

        return ProgressionSegment(
            classification: classification,
            range: rangeStr,
            avgSessionsPerWeek: (avgPerWeek * 10).rounded() / 10,
            magnitude: magnitude
        )
    }

    // MARK: - Helpers

    private static func monthLabel(for date: Date, locale: Locale) -> String {
        let fmt = DateFormatter()
        fmt.locale = locale
        fmt.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return fmt.string(from: date)
    }

    private func buildHistoryRange(first: Date, last: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        return "\(fmt.string(from: first)) to \(fmt.string(from: last))"
    }
}
