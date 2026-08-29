//
//  ExerciseProgressService.swift
//  GymStreak
//

import Foundation

/// The seam that hides where each half of an exercise comparison runs.
///
/// Both halves used to run here, synchronously on the main actor: `compareWithPrevious`
/// issued one unbounded, unprefetched `FetchDescriptor<WorkoutSession>` **per exercise**
/// plus two full `Exercise` library scans per exercise, on every workout finish and every
/// past-workout open (audit P1.6). This type now owns no `ModelContext` at all — it holds
/// the two pure Domain services either side of one `@concurrent` boundary call:
///
/// 1. `ExerciseComparisonBuilder.makeSnapshot` reduces the workout to values, on the main
///    actor, because the workout may be an in-flight session the store has not seen yet.
/// 2. `HistorySnapshotProviding.fetchPreviousPerformances` scans history on the model
///    actor's executor.
/// 3. `ExerciseComparisonBuilder.build` assembles the rows from that snapshot — never from
///    the `@Model` graph, which the caller may have deleted while step 2 ran.
///
/// The exercise **chart** does not come through here — see `ExerciseProgressAggregator`
/// and `docs/progress-charts.md` (audit P1.2).
@MainActor
struct ExerciseProgressService: ExerciseProgressProviding {
    private let historyProvider: any HistorySnapshotProviding

    init(historyProvider: any HistorySnapshotProviding) {
        self.historyProvider = historyProvider
    }

    func compareWithPrevious(workout: WorkoutSession) async -> [ExerciseComparisonResult] {
        // The one read of the `@Model` graph, and it is deliberately before the await: the
        // save sheet compares `WorkoutViewModel.currentSession`, and `cancelWorkout()` can
        // delete that session while the history scan below is in flight. Touching a deleted
        // model is an uncatchable trap (docs/history-delete-race.md).
        let snapshot = ExerciseComparisonBuilder.makeSnapshot(workout: workout)
        guard let previous = try? await historyProvider.fetchPreviousPerformances(snapshot.lookup) else {
            // No rows rather than rows with no predecessor: the callers render the latter
            // as "New exercise" badges, so degrading into it would state something false
            // about the user's history instead of showing nothing.
            return []
        }
        return ExerciseComparisonBuilder.build(snapshot: snapshot, previousPerformances: previous)
    }
}
