//
//  ExerciseDeepDiveAggregator.swift
//  GymStreak
//

import Foundation
import SwiftData
import os

/// Builds an `ExerciseDeepDiveInput` from the historical data the exercise detail screen
/// is showing: one exercise, one selected usage, one load behaviour.
///
/// The narrative sits directly under the chart and speaks in full sentences, so it is
/// *more* likely to be believed than the numbers above it — which is why it resolves rows
/// with the chart's three rules rather than any of its own. See `RowFilter` for identity
/// and load-behaviour homogeneity, and `buildInput` for what a blended `.combined` view
/// deliberately withholds.
///
/// The produced input is `nil` when the selected usage has insufficient history (fewer
/// than 4 completed sets, or fewer than two sessions).
///
/// **Every entry point here fetches and faults SwiftData relationships across all of
/// history, so all of them belong on a model actor.** `SwiftDataHistorySnapshotStore` is
/// the only production caller; `ExerciseDeepDiveFactProviding` is the boundary that gets
/// it there, and `SwiftDataHistorySnapshotProvider`'s `@concurrent` is what keeps it off
/// the main one.
struct ExerciseDeepDiveAggregator {

    private static let logger = Logger(subsystem: "com.gymstreak", category: "ExerciseDeepDiveAggregator")

    // MARK: - Epley

    private static func epley(weight: Double, reps: Int) -> Double {
        weight * (1.0 + Double(reps) / 30.0)  
    }

    // MARK: - Public API

    /// Everything one deep-dive generation needs from history, answered from **one** walk
    /// of the session graph: the narrative's input, and the timestamp its cache key is
    /// stamped with.
    ///
    /// The two used to be separate entry points, each issuing its own unbounded
    /// `FetchDescriptor<WorkoutSession>`, so a single tap fetched all of history twice —
    /// three times counting the cache write after the stream — and did all of it on the
    /// main actor (ticket 02). They are answered together because they are answered from
    /// the same rows: the key must move exactly when the described body of work moves,
    /// and deriving it from a second fetch is the only way the two could ever disagree.
    ///
    /// Called **only** from `SwiftDataHistorySnapshotStore`, on its model actor. It walks
    /// every session's exercise → set graph, which is not main-actor work
    /// (`docs/history-performance.md`).
    ///
    /// - Parameters:
    ///   - exerciseId: id of the live `Exercise` the screen is showing. A value rather
    ///     than the `@Model` itself, because a `PersistentModel` may not cross onto a
    ///     model actor.
    ///   - exerciseName: that same live entry's name, handed down rather than re-derived
    ///     here — so the identity rule below sees exactly the exercise the user is
    ///     looking at, even where two library entries share a name.
    ///   - locale: User's locale (for month label formatting).
    ///   - modelContext: the **model actor's** context for history queries.
    ///   - usage: the usage the exercise detail screen is showing — the selection **and**
    ///     the label the picker used for it — handed down rather than re-derived.
    ///     `ExerciseProgressViewModel` already resolved both, and a second resolution
    ///     could disagree with the menu the user picked from. `.combined` folds every
    ///     usage together, which is what an exercise trained exactly one way always is.
    ///   - now: Injection point for current date (injectable for tests).
    func buildAggregate(
        exerciseId: UUID,
        exerciseName: String,
        locale: Locale,
        modelContext: ModelContext,
        usage: DeepDiveUsage = .combined,
        now: Date = Date()
    ) -> ExerciseDeepDiveAggregate {
        let sessions = fetchSessionsForFullAggregation(modelContext: modelContext)
        let library = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
        let filter = RowFilter(exerciseId: exerciseId, exerciseName: exerciseName, library: library)

        return ExerciseDeepDiveAggregate(
            lastCompletedSetTimestamp: Self.lastCompletedSetTimestamp(
                in: sessions,
                filter: filter,
                usageSelection: usage.selection
            ),
            input: buildInput(
                sessions: sessions,
                filter: filter,
                exerciseName: exerciseName,
                locale: locale,
                usage: usage,
                now: now
            )
        )
    }

    /// Builds the AI Coach deep-dive input for a single exercise, describing **the body
    /// of work the screen is showing**.
    ///
    /// - Returns: `nil` if the selected usage has fewer than 4 completed sets, or fewer
    ///   than two sessions, across all history.
    private func buildInput(
        sessions: [WorkoutSession],
        filter: RowFilter,
        exerciseName: String,
        locale: Locale,
        usage: DeepDiveUsage,
        now: Date
    ) -> ExerciseDeepDiveInput? {
        let usageSelection = usage.selection

        // Only for `.combined`, and only because that is the branch whose answer depends
        // on it: whether combined is a genuine blend or simply the one way this exercise
        // has ever been trained. A selected usage is one usage by definition, so the
        // second all-time pass over history is not run for it.
        let blendedUsageCount = usageSelection == .combined
            ? ExerciseUsageResolver.options(in: sessions, matching: filter.matches).count
            : 1

        let dataPoints = buildDataPoints(
            sessions: sessions,
            filter: filter,
            usageSelection: usageSelection
        )

        // Insufficient data guard: require at least 4 completed sets
        let totalSets = dataPoints.reduce(0) { $0 + $1.setCount }
        guard totalSets >= 4, dataPoints.count >= 2 else { return nil }

        let sortedPoints = dataPoints.sorted { $0.date < $1.date }
        guard let first = sortedPoints.first, let last = sortedPoints.last else { return nil }

        let peak = findPeak(points: sortedPoints, locale: locale)
        let historyRange = buildHistoryRange(first: first.date, last: last.date, locale: locale)

        // A blend states no trend. The first-to-last delta across several usages is
        // decided by which usage happens to sit at each end of the range, which is the
        // very number this screen's Trend card withholds by printing *Gemischt*
        // (`docs/progress-charts.md`). Segments are first-to-last deltas too, so they go
        // with it — a coach that cannot state the trend but announces "improving,
        // +5.0 kg est. 1RM" has withheld nothing.
        guard blendedUsageCount <= 1 else {
            return ExerciseDeepDiveInput(
                locale: locale.identifier,
                exerciseName: exerciseName,
                usageLabel: nil,
                blendedUsageCount: blendedUsageCount,
                totalSessions: sortedPoints.count,
                historyRange: historyRange,
                overallProgression: nil,
                peak: peak,
                strongestSegment: nil,
                currentSegment: nil
            )
        }

        let firstEst = first.bestEst1RM
        let lastEst = last.bestEst1RM
        let deltaKg = lastEst - firstEst
        let percentChange = firstEst > 0 ? Int((deltaKg / firstEst * 100).rounded()) : 0

        let weeklyBuckets = buildWeeklyBuckets(points: sortedPoints)
        let strongestSegment = findStrongestSegment(buckets: weeklyBuckets, locale: locale, now: now)
        let currentSegment = buildCurrentSegment(buckets: weeklyBuckets, locale: locale, now: now)

        return ExerciseDeepDiveInput(
            locale: locale.identifier,
            exerciseName: exerciseName,
            usageLabel: usage.label,
            blendedUsageCount: blendedUsageCount,
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

    /// Every completed session with `workoutExercises` and their `sets` already
    /// registered. **For `buildAggregate` only** — see `lastCompletedSetTimestamp` for why
    /// the appear-time probe must not share it.
    ///
    /// `CompletedSessionFetch.withFullGraph` warns that it is model-actor-only because it
    /// materializes the entire workout graph. That warning is satisfied rather than
    /// tolerated here: since ticket 02 the only caller is `SwiftDataHistorySnapshotStore`,
    /// so this runs on that actor's executor. `buildInput` walks the whole graph anyway —
    /// every session, every matching row, every completed set, and a second all-time pass
    /// for `.combined` — so the prefetch makes its cost smaller, not larger; without it
    /// the same traversal faults once per row and once per set.
    ///
    /// Order is irrelevant to this caller: `buildDataPoints` sorts its points itself,
    /// `ExerciseUsageResolver` ranks descriptors by an explicit comparison, and the cache
    /// timestamp is a `max`.
    private func fetchSessionsForFullAggregation(modelContext: ModelContext) -> [WorkoutSession] {
        (try? CompletedSessionFetch.withFullGraph(in: modelContext)) ?? []
    }

    // MARK: - Cache Key Query

    /// Returns the most recent session date containing a completed set of **the selected
    /// usage** of this exercise, used by `ExerciseDeepDiveViewModel` to build its cache
    /// key. Returns `nil` when no matching completed set is found.
    ///
    /// **Filtered exactly as `buildDataPoints` filters.** Identity is the shared
    /// `ExerciseProgressAggregator.matches(_:exerciseId:exerciseName:nameIsUnique:)`; a
    /// row whose `loadBehavior` differs from the live library's is not part of this
    /// series; and a row belonging to another usage is not part of this narrative. Every
    /// row this admits that the narrative does not describe is a needless cache miss —
    /// and for a free user a miss spends a monthly allowance unit
    /// (`docs/pro-subscription.md` §5e) to regenerate a narrative that had not changed.
    /// It used to accept `we.exerciseId == exerciseId || we.exerciseId == nil` — no name
    /// check at all — so *any* legacy row in the newest session moved this key.
    ///
    /// This is the **appear-time** probe (`checkCache`). `buildAggregate` answers the same
    /// question from the graph it already holds, via the shared helper below, so a
    /// generation never runs both.
    func lastCompletedSetTimestamp(
        exerciseId: UUID,
        modelContext: ModelContext,
        usageSelection: ExerciseUsageSelection = .combined
    ) -> Date? {
        let library = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
        // Without the live entry there is no name to match on, so only the id can be
        // matched — which is the conservative half of the rule, never the guessing half.
        // `RowFilter` then falls back to `.resistance`, the same fallback the chart's
        // `buildSnapshot` takes for an exercise the library no longer holds.
        let exerciseName = library.first { $0.id == exerciseId }?.name ?? ""
        let filter = RowFilter(exerciseId: exerciseId, exerciseName: exerciseName, library: library)

        // Its own fetch, deliberately **not** `fetchSessionsForFullAggregation`. This runs
        // from `checkCache` on the screen's `.task` — on appear and on every exercise or
        // usage switch — and it returns at the first matching session, which is normally
        // the newest one. Materializing every `WorkoutExercise` and every `WorkoutSet` in
        // the database to read one session is the `docs/history-performance.md` walk,
        // bought for nothing. That the walk is off the main actor since ticket 02 does not
        // make it free: this probe shares the History model actor with the chart load
        // happening on the same screen at the same moment.
        //
        // One direct key path is the documented use of `relationshipKeyPathsForPrefetching`
        // (as in `CompletedSessionFetch.withRoutine`): it saves the per-row fault on the
        // sessions actually visited, and the set fault stays per visited row.
        //
        // The sort is written here because the loop depends on it: newest first, so the
        // first match is the answer.
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endTime != nil },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.workoutExercises]
        guard let sessions = try? modelContext.fetch(descriptor) else { return nil }

        for session in sessions where Self.hasCompletedSet(
            in: session,
            filter: filter,
            usageSelection: usageSelection
        ) {
            return session.startTime
        }
        return nil
    }

    /// The same answer as `lastCompletedSetTimestamp(exerciseId:modelContext:usageSelection:)`,
    /// read off a graph the caller has already fetched — which is what lets one generation
    /// walk history once instead of twice.
    ///
    /// A `max` rather than a first-match, because `fetchSessionsForFullAggregation`
    /// deliberately imposes no order.
    private static func lastCompletedSetTimestamp(
        in sessions: [WorkoutSession],
        filter: RowFilter,
        usageSelection: ExerciseUsageSelection
    ) -> Date? {
        sessions
            .filter { hasCompletedSet(in: $0, filter: filter, usageSelection: usageSelection) }
            .map(\.startTime)
            .max()
    }

    /// Whether this session holds a completed set that the narrative describes. One
    /// definition, shared by both timestamp paths, so the appear-time probe and the
    /// generation can never key on different rows.
    private static func hasCompletedSet(
        in session: WorkoutSession,
        filter: RowFilter,
        usageSelection: ExerciseUsageSelection
    ) -> Bool {
        ExerciseUsageResolver
            .keyedRows(in: session, matching: filter.matches)
            .contains {
                ExerciseUsageResolver.belongs($0.key, to: usageSelection)
                    && $0.exercise.setsList.contains(where: \.isCompleted)
            }
    }

    // MARK: - Row filter

    /// The two rules that decide which history rows make up one series: **identity** — the
    /// shared `ExerciseProgressAggregator.matches(_:exerciseId:exerciseName:nameIsUnique:)`,
    /// deliberately not a local copy — and **`loadBehavior` homogeneity**. Resolved once
    /// from the live library, exactly as `ExerciseProgressAggregator.buildSnapshot`
    /// resolves them for the chart on the same screen.
    ///
    /// This type used to carry its own identity rule that applied the legacy name fallback
    /// **without** the uniqueness gate: `we.exerciseId == nil && name matches`. Where two
    /// live exercises share a name, that claimed every ambiguous pre-`exerciseId` row for
    /// *both* of them — so the coach narrated a trend over a series blended across two
    /// different exercises, and did it on a screen whose chart deliberately drops those
    /// rows. Reported from a device check: the coach read "in den letzten 19 Sitzungen …
    /// -43%" beside a chart and a row that both said 15 workouts. Attribution does not save
    /// this path either — double-counting survives what dropping does not.
    ///
    /// The `loadBehavior` half keeps the entered number meaning one thing throughout a
    /// series. A uniquely-named exercise whose library load behaviour changed after some
    /// workouts were logged otherwise has a narrative mixing counterweight *assistance*
    /// values with physical loads (`docs/assisted-exercise-progress.md`).
    ///
    /// `ExerciseProgressAggregator`, `FortschrittAggregator` and `PeriodRecapAggregator`
    /// all gate the fallback. Four copies of one rule is how three of them stayed right
    /// while this one drifted, so this one is a call, not a copy — in every place this
    /// type resolves a row: `buildInput`, `buildDataPoints` and `lastCompletedSetTimestamp`
    /// all go through this one value.
    private struct RowFilter {
        let exerciseId: UUID?
        let exerciseName: String
        let nameIsUnique: Bool
        let loadBehavior: ExerciseLoadBehavior

        init(exerciseId: UUID?, exerciseName: String, library: [Exercise]) {
            self.exerciseId = exerciseId
            self.exerciseName = exerciseName
            self.nameIsUnique = ExerciseProgressAggregator.isNameUnique(exerciseName, in: library)
            self.loadBehavior = ExerciseProgressAggregator.loadBehavior(
                exerciseId: exerciseId,
                exerciseName: exerciseName,
                in: library
            )
        }

        func matches(_ row: WorkoutExercise) -> Bool {
            ExerciseProgressAggregator.matches(
                row,
                exerciseId: exerciseId,
                exerciseName: exerciseName,
                nameIsUnique: nameIsUnique
            ) && row.loadBehavior == loadBehavior
        }
    }

    // MARK: - Per-Session Data Points

    private struct SessionDataPoint {
        let date: Date
        let bestEst1RM: Double
        let bestWeight: Double
        let bestReps: Int
        let setCount: Int
    }

    /// One point per session that holds a completed set of the selected usage.
    ///
    /// Rows are keyed by `ExerciseUsageResolver.keyedRows(in:matching:)` and filtered by
    /// `belongs(_:to:)` — the same two calls `ExerciseProgressAggregator.buildProgress`
    /// makes — so the coach's session count is the chart's session count and its
    /// progression is computed over the chart's points.
    private func buildDataPoints(
        sessions: [WorkoutSession],
        filter: RowFilter,
        usageSelection: ExerciseUsageSelection
    ) -> [SessionDataPoint] {
        var points: [SessionDataPoint] = []

        for session in sessions {
            var bestEst: Double = 0
            var bestW: Double = 0
            var bestR: Int = 0
            var setCount = 0

            let rows = ExerciseUsageResolver
                .keyedRows(in: session, matching: filter.matches)
                .filter { ExerciseUsageResolver.belongs($0.key, to: usageSelection) }
                .map(\.exercise)

            for we in rows {
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

    /// The period the analysis covers, in the reader's own language — "Juli 2026 –
    /// August 2026", collapsing to a single label when both ends fall in one month.
    ///
    /// It used to be `"2026-07 to 2026-08"`, a machine format handed straight to a
    /// language model, and the model echoed it: the narrative opened "in den letzten
    /// 2026-07 und 2026-08". Exactly the failure the workout-analysis surface already
    /// hit with raw ISO dates (`docs/ai-coach.md` §4) — so this uses the same localized
    /// `MMMM yyyy` that `monthLabel` builds for the peak.
    private func buildHistoryRange(first: Date, last: Date, locale: Locale) -> String {
        let start = Self.monthLabel(for: first, locale: locale)
        let end = Self.monthLabel(for: last, locale: locale)
        return start == end ? start : "\(start) – \(end)"
    }
}
