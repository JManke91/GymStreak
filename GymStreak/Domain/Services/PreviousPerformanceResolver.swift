//
//  PreviousPerformanceResolver.swift
//  GymStreak
//

import Foundation

/// Answers "what did I lift last time?" for every exercise of one workout, in a single
/// pass over an already-fetched session graph.
///
/// Extracted from `ExerciseProgressService` (audit P1.6), which ran this synchronously on
/// the main actor and issued **one unbounded `FetchDescriptor<WorkoutSession>` per
/// exercise** — plus two full `Exercise` library scans per exercise — every time a
/// workout was finished or a past workout opened. Neither fetch prefetched relationships,
/// so each session then faulted its exercises and sets one row at a time. All of it now
/// happens once, inside `SwiftDataHistorySnapshotStore`'s model actor, over the shared
/// prefetch-correct `CompletedSessionFetch.withFullGraph` result.
///
/// Pure and isolation-agnostic. **Never add `@MainActor`** (`docs/swift6-concurrency.md`
/// §10 rule 3): the model actor calls it from its own executor. It takes already-fetched
/// models and returns immutable values, so it is directly testable without a fetch.
enum PreviousPerformanceResolver {

    /// Resolves each exercise of `lookup` against the most recent comparable session.
    ///
    /// - Parameters:
    ///   - lookup: the workout being compared, as values (see `PreviousPerformanceLookup`).
    ///   - sessions: completed sessions, in any order — this sorts what it needs rather
    ///     than relying on the caller's fetch order.
    ///   - liveExercises: the user's `Exercise` library, which decides whether a legacy
    ///     row's name match is unambiguous.
    /// - Returns: the predecessor keyed by `PreviousPerformanceLookup.Query.workoutExerciseId`.
    ///   Exercises with no comparable history are simply absent.
    static func resolve(
        lookup: PreviousPerformanceLookup,
        sessions: [WorkoutSession],
        liveExercises: [Exercise]
    ) -> [UUID: PreviousExercisePerformance] {
        // One shared candidate list for the whole workout instead of one fetch per
        // exercise. This is the finding.
        //
        // The `id` tie-break is not cosmetic. Ordering used to come from the fetch's
        // `SortDescriptor`; `sorted(by:)` is not a stable sort, so two sessions sharing a
        // `startTime` to the last bit would otherwise yield an unspecified — and possibly
        // run-to-run different — predecessor. The UI cannot produce that collision, but
        // HealthKit recovery and watch ingestion both take `startTime` from outside.
        let candidates = sessions
            .filter { $0.endTime != nil && $0.startTime < lookup.before }
            .sorted {
                $0.startTime == $1.startTime
                    ? $0.id.uuidString > $1.id.uuidString
                    : $0.startTime > $1.startTime
            }

        // The live library was rescanned twice per exercise before; count names once.
        var liveNameCounts: [String: Int] = [:]
        for exercise in liveExercises {
            liveNameCounts[exercise.name.lowercased(), default: 0] += 1
        }

        var resolved: [UUID: PreviousExercisePerformance] = [:]
        for query in lookup.exercises {
            let nameIsUnique = (liveNameCounts[query.exerciseName.lowercased()] ?? 0) <= 1
            guard let performance = previousPerformance(
                for: query,
                occurrenceIndex: occurrenceIndex(of: query, in: lookup.exercises, nameIsUnique: nameIsUnique),
                routineId: lookup.routineId,
                nameIsUnique: nameIsUnique,
                candidates: candidates
            ) else { continue }
            resolved[query.workoutExerciseId] = performance
        }
        return resolved
    }

    // MARK: - Private

    /// Where this exercise sits among the workout's *own* repeats of it.
    ///
    /// The legacy identity for workouts recorded before routine-slot ids were
    /// snapshotted: a routine that trains the same exercise twice (heavy first, high-rep
    /// later) has to compare each occurrence with its own counterpart.
    private static func occurrenceIndex(
        of query: PreviousPerformanceLookup.Query,
        in exercises: [PreviousPerformanceLookup.Query],
        nameIsUnique: Bool
    ) -> Int {
        let repeats = exercises.filter {
            ExerciseProgressAggregator.matches(
                candidateExerciseId: $0.exerciseId,
                candidateExerciseName: $0.exerciseName,
                exerciseId: query.exerciseId,
                exerciseName: query.exerciseName,
                nameIsUnique: nameIsUnique
            ) && $0.loadBehavior == query.loadBehavior
        }
        return repeats.firstIndex { $0.workoutExerciseId == query.workoutExerciseId } ?? 0
    }

    /// The most recent candidate session containing the same ordered occurrence.
    private static func previousPerformance(
        for query: PreviousPerformanceLookup.Query,
        occurrenceIndex: Int,
        routineId: UUID?,
        nameIsUnique: Bool,
        candidates: [WorkoutSession]
    ) -> PreviousExercisePerformance? {
        for session in candidates {
            let matching = session.workoutExercisesList
                .filter {
                    ExerciseProgressAggregator.matches(
                        $0,
                        exerciseId: query.exerciseId,
                        exerciseName: query.exerciseName,
                        nameIsUnique: nameIsUnique
                    ) && $0.loadBehavior == query.loadBehavior
                }
                .sorted { $0.order < $1.order }

            let exercise: WorkoutExercise
            if let routineExerciseId = query.routineExerciseId,
               let exactMatch = matching.first(where: { $0.routineExerciseId == routineExerciseId }) {
                exercise = exactMatch
            } else {
                // Occurrence order is only meaningful inside a proven routine context. If
                // the relationship no longer exists, a display-name match could silently
                // join two routines with the same name, so legacy comparison stays empty.
                guard let routineId, session.routine?.id == routineId else { continue }
                let legacyMatches = query.routineExerciseId == nil
                    ? matching
                    : matching.filter { $0.routineExerciseId == nil }
                guard legacyMatches.indices.contains(occurrenceIndex) else { continue }
                exercise = legacyMatches[occurrenceIndex]
            }

            let usePlanned = exercise.progressiveOverloadApplied
            let sets = exercise.setsList.sorted { $0.order < $1.order }.map { set in
                PreviousExercisePerformance.SetPerformance(
                    reps: usePlanned ? set.plannedReps : set.actualReps,
                    weight: usePlanned ? set.plannedWeight : set.actualWeight,
                    isCompleted: set.isCompleted
                )
            }

            return PreviousExercisePerformance(
                date: session.startTime,
                routineName: session.routineName,
                sets: sets,
                effectiveTotalVolume: ExerciseLoadMetrics.effectiveVolume(
                    from: exercise.setsList.filter(\.isCompleted),
                    usePlannedValues: usePlanned,
                    behavior: exercise.loadBehavior,
                    bodyWeightKg: session.bodyWeightKg
                )
            )
        }
        return nil
    }
}
