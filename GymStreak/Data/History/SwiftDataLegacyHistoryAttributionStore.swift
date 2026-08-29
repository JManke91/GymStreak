//
//  SwiftDataLegacyHistoryAttributionStore.swift
//  GymStreak
//

import Foundation
import SwiftData

/// Constructs the SwiftData model actor outside MainActor, then forwards the one write to it.
///
/// Mirrors `SwiftDataHistorySnapshotProvider` — including the `Task.detached`
/// construction, because `AppDependencies` is `@MainActor` and Apple does not document
/// construction-site affinity as a `@ModelActor` guarantee.
///
/// A *second* model actor next to the History one is intentional. The History actor is
/// documented as a read boundary over the completed-session graph, and its `ModelContext`
/// is shared by several screens; committing a write through it would put a `save()` on the
/// context those reads run against. This one owns its own context, exists only for a rare
/// user-confirmed repair, and holds no cached state between calls.
struct SwiftDataLegacyHistoryAttributionProvider: LegacyHistoryAttributing {
    private let storeTask: Task<SwiftDataLegacyHistoryAttributionStore, Never>

    /// This is the third `@ModelActor` over the same store, and it is exposed to the same
    /// cross-context delete race as the other two: it fetches `WorkoutExercise` rows, then
    /// traverses `workoutSession?.endTime` on each and writes to them. A completed-session
    /// delete landing in between would trap. See `HistoryStoreGate`.
    private let gate: HistoryStoreGate

    /// - Parameter gate: **`AppDependencies`' shared gate** — the same instance the History
    ///   and chat providers get. Not defaulted, for the reason given on those two.
    init(modelContainer: ModelContainer, gate: HistoryStoreGate) {
        self.gate = gate
        self.storeTask = Task.detached(priority: .userInitiated) {
            SwiftDataLegacyHistoryAttributionStore(modelContainer: modelContainer)
        }
    }

    // `@concurrent` for the same load-bearing reason as every method on
    // `SwiftDataHistorySnapshotProvider`: `SWIFT_APPROACHABLE_CONCURRENCY` would
    // otherwise run the fetch and the save on the calling `@MainActor` ViewModel's
    // actor. See `docs/swift6-concurrency.md` §1.
    @concurrent func attributeLegacyRows(
        named exerciseName: String,
        to exerciseId: UUID
    ) async throws -> Int {
        let store = await storeTask.value
        return try await gate.withAccess {
            try await store.attributeLegacyRows(named: exerciseName, to: exerciseId)
        }
    }
}

@ModelActor
actor SwiftDataLegacyHistoryAttributionStore {

    /// Sets the missing library link on every legacy row of one exercise name.
    ///
    /// The fetch is narrowed in the store to rows that carry no `exerciseId` — the only
    /// candidates — rather than walking the completed-session graph the History actor
    /// fetches. Every write path in the app has set `exerciseId` since it existed, so this
    /// predicate selects legacy data and nothing else, and it stays small even for a user
    /// with years of history.
    ///
    /// The name comparison and the completed-session check happen in Swift because
    /// SwiftData's `#Predicate` has neither case-insensitive equality nor a documented
    /// comparison across the optional `workoutSession` relationship; both run only over
    /// the already-narrowed rows.
    ///
    /// **Scope matches what the banner is about: finished workouts.** A row belonging to
    /// an in-progress session, or to no session at all, is left alone — the user was told
    /// about *history*, and a workout still being performed is not that. Within a finished
    /// session every matching row is linked, including one whose sets were all left
    /// uncompleted: the count the banner shows deliberately excludes those (they would
    /// render nowhere even once linked, so promising them would be a second wrong number),
    /// but a row is a row, and leaving one behind would keep the same workout half-legacy.
    ///
    /// Writes exactly one field. `exerciseName`, `muscleGroups` and `loadBehaviorRaw` are
    /// the denormalised record of what was performed and are deliberately left alone —
    /// re-deriving them from today's library is how an old session would silently change
    /// meaning.
    func attributeLegacyRows(named exerciseName: String, to exerciseId: UUID) throws -> Int {
        try Task.checkCancellation()
        let descriptor = FetchDescriptor<WorkoutExercise>(
            predicate: #Predicate { $0.exerciseId == nil }
        )
        let target = exerciseName.lowercased()
        let rows = try modelContext.fetch(descriptor).filter {
            ExerciseProgressAggregator.isUnattributedLegacyRow($0, matching: target)
                && $0.workoutSession?.endTime != nil
        }
        guard !rows.isEmpty else { return 0 }

        for row in rows {
            row.exerciseId = exerciseId
        }
        try modelContext.save()
        return rows.count
    }
}
