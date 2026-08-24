//
//  ExerciseProgressAggregator.swift
//  GymStreak
//

import Foundation
import SwiftData

/// Pure aggregator that turns completed `WorkoutSession`s into the exercise detail
/// screen's chart series and its "recent sets" list.
///
/// Extracted from `ExerciseProgressService` (audit P1.2) so the whole-history
/// traversal can run inside `SwiftDataHistorySnapshotStore`'s model actor instead of
/// synchronously on the main actor. Nothing here may become `@MainActor`: the actor
/// calls it from its own executor (`docs/swift6-concurrency.md` §10 rule 3), and the
/// same rule is why it lives in `Domain/Services/` rather than next to the store.
///
/// Every entry point takes already-fetched models and returns immutable values, so it
/// is directly testable without a `ModelContext` fetch.
struct ExerciseProgressAggregator {

    // MARK: - Combined entry point

    /// Builds both halves of the exercise detail screen from one session array.
    ///
    /// - Parameters:
    ///   - sessions: completed sessions, in any order — each builder sorts what it needs.
    ///   - liveExercises: the user's `Exercise` library, used to resolve load behaviour
    ///     and to decide whether a legacy name match is unambiguous.
    ///   - startDate: chart window lower bound. Only the chart series is windowed;
    ///     the recent-usage list is deliberately all-time, matching the previous behaviour.
    ///   - recentSessionLimit: caps the recent-usage list by **sessions**, not by cards —
    ///     a workout that trained the exercise twice contributes two cards but counts once.
    ///   - requestedUsage: which usage to chart, or `nil` on first open to take the
    ///     default. Resolved here, and reported back as `snapshot.selectedUsage`, so the
    ///     screen never has to fetch once to learn the options and again to apply one.
    ///     The usage **options** are all-time, so neither the menu's contents nor the
    ///     default selection move when the user changes the timeframe.
    static func buildSnapshot(
        sessions: [WorkoutSession],
        liveExercises: [Exercise],
        exerciseName: String,
        exerciseId: UUID?,
        startDate: Date,
        recentSessionLimit: Int,
        requestedUsage: ExerciseUsageSelection? = nil
    ) -> ExerciseProgressSnapshot {
        let nameIsUnique = isNameUnique(exerciseName, in: liveExercises)
        let behavior = loadBehavior(
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            in: liveExercises
        )
        // All-time, not `windowedSessions`: a menu that reshuffles on every timeframe tap
        // is what the reporter saw as the screen "suddenly showing different options".
        let options = ExerciseUsageResolver.options(in: sessions) { exercise in
            matches(exercise, exerciseId: exerciseId, exerciseName: exerciseName, nameIsUnique: nameIsUnique)
                && exercise.loadBehavior == behavior
        }
        let selection = ExerciseUsageResolver.resolveSelection(
            requested: requestedUsage,
            options: options
        )

        return ExerciseProgressSnapshot(
            data: buildProgress(
                sessions: sessions,
                exerciseName: exerciseName,
                exerciseId: exerciseId,
                nameIsUnique: nameIsUnique,
                loadBehavior: behavior,
                startDate: startDate,
                usageSelection: selection
            ),
            recentUsages: buildRecentUsages(
                sessions: sessions,
                exerciseName: exerciseName,
                exerciseId: exerciseId,
                nameIsUnique: nameIsUnique,
                loadBehavior: behavior,
                limit: recentSessionLimit,
                usageSelection: selection
            ),
            availableUsages: options,
            selectedUsage: selection
        )
    }

    /// Completed sessions inside the chart window, oldest first. The chart series only —
    /// the picker's options and the recent-sets list are both all-time.
    static func windowedSessions(_ sessions: [WorkoutSession], startDate: Date) -> [WorkoutSession] {
        sessions
            .filter { $0.endTime != nil && $0.startTime >= startDate }
            .sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Chart series

    /// One data point per session that contains at least one completed set of the exercise
    /// **in the selected usage**.
    ///
    /// - Parameter usageSelection: the routine slot to chart, or `.combined` for every usage folded
    ///   together. Selecting a usage is what stops a workout trained heavy *and* light from
    ///   collapsing into one `max`: each usage gets its own point for that session, so the
    ///   series reads as a progression instead of alternating between two loads.
    static func buildProgress(
        sessions: [WorkoutSession],
        exerciseName: String,
        exerciseId: UUID?,
        nameIsUnique: Bool,
        loadBehavior: ExerciseLoadBehavior,
        startDate: Date,
        usageSelection: ExerciseUsageSelection = .combined
    ) -> ExerciseProgressData {
        let windowed = windowedSessions(sessions, startDate: startDate)

        // Keyed by the resolver, so a workout holding two rows of one slot yields one
        // series per row instead of collapsing both into a single session `max`.
        let matchedBySession = windowed.map { session in
            (
                session,
                ExerciseUsageResolver.keyedRows(in: session) {
                    matches($0, exerciseId: exerciseId, exerciseName: exerciseName, nameIsUnique: nameIsUnique)
                        && $0.loadBehavior == loadBehavior
                }
                .filter { ExerciseUsageResolver.belongs($0.key, to: usageSelection) }
                .map(\.exercise)
            )
        }
        let relevant = matchedBySession.filter { !$0.1.isEmpty }
        let usesEffectiveLoad = loadBehavior.isCounterweightAssistance
            && !relevant.isEmpty
            && relevant.allSatisfy { $0.0.bodyWeightKg != nil }
        var dataPoints: [ExerciseProgressDataPoint] = []

        for (session, matchingExercises) in matchedBySession {

            // Aggregate all matching exercises into a single data point per session
            var sessionMaxWeight: Double = 0
            var sessionTotalVolume: Double = 0
            var sessionTotalReps: Int = 0
            var sessionTotalSets: Int = 0
            var sessionBest1RM: Double = 0
            var hasCompletedSets = false
            var hasAssistanceValue = false

            for exercise in matchingExercises {
                let completedSets = exercise.setsList.filter(\.isCompleted)
                guard !completedSets.isEmpty else { continue }
                hasCompletedSets = true

                let usePlanned = exercise.progressiveOverloadApplied
                let enteredWeights = completedSets.map { usePlanned ? $0.plannedWeight : $0.actualWeight }
                if loadBehavior.isCounterweightAssistance && !usesEffectiveLoad {
                    let leastAssistance = enteredWeights.min() ?? 0
                    sessionMaxWeight = hasAssistanceValue
                        ? min(sessionMaxWeight, leastAssistance)
                        : leastAssistance
                    hasAssistanceValue = true
                } else {
                    let effectiveWeights = enteredWeights.compactMap {
                        ExerciseLoadMetrics.effectiveWeight(
                            enteredWeight: $0,
                            behavior: loadBehavior,
                            bodyWeightKg: session.bodyWeightKg
                        )
                    }
                    sessionMaxWeight = max(sessionMaxWeight, effectiveWeights.max() ?? 0)
                }

                if usesEffectiveLoad || !loadBehavior.isCounterweightAssistance {
                    sessionTotalVolume += completedSets.reduce(0) {
                        let entered = usePlanned ? $1.plannedWeight : $1.actualWeight
                        let reps = usePlanned ? $1.plannedReps : $1.actualReps
                        let weight = ExerciseLoadMetrics.effectiveWeight(
                            enteredWeight: entered,
                            behavior: loadBehavior,
                            bodyWeightKg: session.bodyWeightKg
                        ) ?? 0
                        return $0 + (weight * Double(reps))
                    }
                }
                sessionTotalReps += completedSets.reduce(0) { $0 + (usePlanned ? $1.plannedReps : $1.actualReps) }
                sessionTotalSets += completedSets.count

                let estimated1RM = usesEffectiveLoad || !loadBehavior.isCounterweightAssistance
                    ? bestEstimated1RM(
                        from: completedSets,
                        usePlannedValues: usePlanned,
                        behavior: loadBehavior,
                        bodyWeightKg: session.bodyWeightKg
                    )
                    : 0
                sessionBest1RM = max(sessionBest1RM, estimated1RM)
            }

            guard hasCompletedSets else { continue }

            dataPoints.append(
                ExerciseProgressDataPoint(
                    date: session.startTime,
                    maxWeight: sessionMaxWeight,
                    estimated1RM: sessionBest1RM,
                    totalVolume: sessionTotalVolume,
                    totalSets: sessionTotalSets,
                    totalReps: sessionTotalReps,
                    workoutSessionId: session.id
                )
            )
        }

        return ExerciseProgressData(
            exerciseName: exerciseName,
            dataPoints: dataPoints,
            loadBehavior: loadBehavior,
            usesEffectiveLoad: usesEffectiveLoad
        )
    }

    // MARK: - Recent usages

    /// Every usage of the exercise in each of the `limit` most recent sessions that
    /// contain completed sets of it — one card per usage, newest session first.
    ///
    /// **One card per usage, not per session.** This used to keep
    /// `workoutExercisesList.first(where:)` and silently drop the rest, so a workout
    /// that trained the exercise both heavy and light showed only one of the two blocks,
    /// contradicting the chart above it (which takes the max across all of them) on the
    /// same screen. Every matching instance now contributes its completed sets, tagged
    /// with the `ExerciseUsage` they belong to.
    ///
    /// **Ordering is explicit, never inherited.** The blocks of one session come from
    /// `ExerciseUsageResolver.keyedRows`, which sorts by `WorkoutExercise.order` — the
    /// sequence the user actually performed — with `id` as a total-order tiebreak, rather
    /// than trusting the raw to-many array. That is also where each block's usage key
    /// (slot **and** occurrence within the session) is assigned, so this list and the
    /// chart above it can never disagree about which rows are the same piece of work.
    /// Sets keep their existing `WorkoutSet.order` sort inside each block.
    ///
    /// **`loadBehavior` is filtered exactly as the chart filters it** (deliberate change:
    /// this list used to apply no filter). Keeping a block the chart excluded is what
    /// produced two panels disagreeing about the same workout, which is the defect this
    /// ticket exists to end. It still ignores the selected timeframe — the list is all-time.
    ///
    /// **The picker filters this list too.** With a usage selected the cap still counts
    /// sessions, so the list reaches back `limit` workouts *of that usage* rather than
    /// showing whatever survives a post-hoc filter.
    ///
    /// - Parameter limit: a **session** cap. Showing every usage must not shrink how far
    ///   back the list reaches, so a two-usage workout emits two cards and counts once.
    ///   The rendered stack therefore scales with the routine's shape, not with history
    ///   length, and stays small enough to remain non-lazy.
    static func buildRecentUsages(
        sessions: [WorkoutSession],
        exerciseName: String,
        exerciseId: UUID?,
        nameIsUnique: Bool,
        loadBehavior: ExerciseLoadBehavior,
        limit: Int,
        usageSelection: ExerciseUsageSelection = .combined
    ) -> [ExerciseRecentUsage] {
        let ordered = sessions
            .filter { $0.endTime != nil }
            .sorted { $0.startTime > $1.startTime }

        var collected: [ExerciseRecentUsage] = []
        var sessionsCollected = 0
        for session in ordered {
            let matching = ExerciseUsageResolver.keyedRows(in: session) {
                matches($0, exerciseId: exerciseId, exerciseName: exerciseName, nameIsUnique: nameIsUnique)
                    && $0.loadBehavior == loadBehavior
            }
            .filter { ExerciseUsageResolver.belongs($0.key, to: usageSelection) }

            var cards: [ExerciseRecentUsage] = []
            for (exercise, key) in matching {
                let usePlanned = exercise.progressiveOverloadApplied
                let entries = exercise.setsList
                    .sorted { $0.order < $1.order }
                    .filter(\.isCompleted)
                    .map { set in
                        ExerciseRecentUsage.SetEntry(
                            id: set.id,
                            weight: usePlanned ? set.plannedWeight : set.actualWeight,
                            reps: usePlanned ? set.plannedReps : set.actualReps
                        )
                    }
                guard !entries.isEmpty else { continue }

                cards.append(
                    ExerciseRecentUsage(
                        id: exercise.id,
                        workoutSessionId: session.id,
                        date: session.startTime,
                        usage: ExerciseUsageResolver.usage(
                            of: exercise,
                            in: session,
                            occurrence: key.occurrence
                        ),
                        sets: entries
                    )
                )
            }

            guard !cards.isEmpty else { continue }
            collected.append(contentsOf: cards)
            sessionsCollected += 1
            if sessionsCollected >= limit { break }
        }
        return collected
    }

    // The usage a row belongs to, the slot-matching rule and the picker's options all
    // live in `ExerciseUsageResolver` — `PreviousPerformanceResolver` shares them, so
    // they may not live inside the chart's aggregator.

    // MARK: - Identity resolution

    /// Decides whether a `WorkoutExercise` belongs to the exercise the caller is asking about.
    ///
    /// When an `exerciseId` is provided, an exact id match always wins. The case-insensitive
    /// name fallback (for legacy rows where `WorkoutExercise.exerciseId` is `nil`) is **only**
    /// used when `nameIsUnique` is true — i.e. there is exactly one live `Exercise` with that
    /// name. When two live exercises share a name (e.g. "Biceps Curls" with dumbbell and
    /// barbell variants), legacy untagged rows are ambiguous, so we drop them from both
    /// charts rather than double-count them under each variant.
    static func matches(
        _ exercise: WorkoutExercise,
        exerciseId: UUID?,
        exerciseName: String,
        nameIsUnique: Bool
    ) -> Bool {
        matches(
            candidateExerciseId: exercise.exerciseId,
            candidateExerciseName: exercise.exerciseName,
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            nameIsUnique: nameIsUnique
        )
    }

    /// The rule above, over values rather than a `WorkoutExercise`.
    ///
    /// `PreviousPerformanceResolver` also has to apply it to the *current* workout's
    /// exercises, which reach it as `PreviousPerformanceLookup.Query` values because no
    /// `@Model` may cross into the model actor (audit P1.6). One implementation, so the
    /// two sides of a comparison can never disagree about what counts as the same
    /// exercise.
    static func matches(
        candidateExerciseId: UUID?,
        candidateExerciseName: String,
        exerciseId: UUID?,
        exerciseName: String,
        nameIsUnique: Bool
    ) -> Bool {
        if let exerciseId {
            if candidateExerciseId == exerciseId { return true }
            if nameIsUnique,
               candidateExerciseId == nil,
               candidateExerciseName.lowercased() == exerciseName.lowercased() {
                return true
            }
            return false
        }
        if nameIsUnique {
            return candidateExerciseName.lowercased() == exerciseName.lowercased()
        }
        return false
    }

    /// Whether `name` is unique (case-insensitive) among the user's live `Exercise` library.
    /// Drives the legacy-row name fallback in `matches(_:exerciseId:exerciseName:nameIsUnique:)`.
    static func isNameUnique(_ name: String, in liveExercises: [Exercise]) -> Bool {
        let target = name.lowercased()
        return liveExercises.filter { $0.name.lowercased() == target }.count <= 1
    }

    /// The live library's load behaviour for the charted exercise, resolved by id when
    /// available and by name otherwise. Falls back to `.resistance` for exercises that
    /// no longer exist in the library.
    static func loadBehavior(
        exerciseId: UUID?,
        exerciseName: String,
        in liveExercises: [Exercise]
    ) -> ExerciseLoadBehavior {
        if let exerciseId, let exercise = liveExercises.first(where: { $0.id == exerciseId }) {
            return exercise.loadBehavior
        }
        return liveExercises
            .first { $0.name.caseInsensitiveCompare(exerciseName) == .orderedSame }?
            .loadBehavior ?? .resistance
    }

    // MARK: - Private helpers

    /// Highest Epley-estimated 1RM across the given sets.
    private static func bestEstimated1RM(
        from sets: [WorkoutSet],
        usePlannedValues: Bool,
        behavior: ExerciseLoadBehavior,
        bodyWeightKg: Double?
    ) -> Double {
        var best1RM: Double = 0

        for set in sets {
            let enteredWeight = usePlannedValues ? set.plannedWeight : set.actualWeight
            let reps = usePlannedValues ? set.plannedReps : set.actualReps
            guard set.isCompleted,
                  let weight = ExerciseLoadMetrics.effectiveWeight(
                    enteredWeight: enteredWeight,
                    behavior: behavior,
                    bodyWeightKg: bodyWeightKg
                  ),
                  weight > 0 else { continue }

            best1RM = max(best1RM, ExerciseLoadMetrics.estimatedOneRepMax(weight: weight, reps: reps))
        }

        return best1RM
    }
}
