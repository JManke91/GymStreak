//
//  SwiftDataHistorySnapshotStore.swift
//  GymStreak
//

import Foundation
import OSLog
import SwiftData

/// Constructs the SwiftData model actor outside MainActor, then forwards structured reads to it.
///
/// `AppDependencies` is MainActor, and direct construction there ran this store on the main thread
/// in the 240-session heartbeat test. Apple does not document construction-site affinity as a
/// `@ModelActor` guarantee, so `Task.detached` provides the explicit non-MainActor construction
/// contract. It is deliberately limited to constructing the stable actor: it does not receive or
/// process models, and actual fetch tasks retain normal caller cancellation through the actor
/// methods and their explicit cancellation checks.
struct SwiftDataHistorySnapshotProvider: HistorySnapshotProviding {
    private let storeTask: Task<SwiftDataHistorySnapshotStore, Never>

    init(modelContainer: ModelContainer) {
        self.storeTask = Task.detached(priority: .userInitiated) {
            SwiftDataHistorySnapshotStore(modelContainer: modelContainer)
        }
    }

    func fetchTrainingSnapshot(referenceDate: Date) async throws -> HistorySnapshot {
        let store = await storeTask.value
        return try await store.fetchTrainingSnapshot(referenceDate: referenceDate)
    }

    func fetchFortschrittSnapshot() async throws -> [FortschrittExerciseModel] {
        let store = await storeTask.value
        return try await store.fetchFortschrittSnapshot()
    }

    func fetchPRDetails(
        sessionID: UUID
    ) async throws -> [UUID: PersonalRecordService.PRDetail] {
        let store = await storeTask.value
        return try await store.fetchPRDetails(sessionID: sessionID)
    }
}

/// Actor-confined read model for the History feature.
///
/// Every unbounded fetch, relationship fault and whole-history aggregation happens on this
/// SwiftData executor. No `PersistentModel` crosses the boundary; callers receive immutable,
/// `Sendable` snapshots and resolve a single main-context model by UUID only for detail/delete.
@ModelActor
actor SwiftDataHistorySnapshotStore: HistorySnapshotProviding {
    private let signposter = OSSignposter(
        subsystem: "com.shotat24fps.GymStreak",
        category: "History"
    )

    func fetchTrainingSnapshot(referenceDate: Date) async throws -> HistorySnapshot {
        try Task.checkCancellation()
        let sessions = try measured("HistoryFetchSessions") {
            try fetchCompletedSessions()
        }
        let routines = try measured("HistoryFetchRoutines") {
            var descriptor = FetchDescriptor<Routine>()
            descriptor.relationshipKeyPathsForPrefetching = [\.schedule]
            return try modelContext.fetch(descriptor)
        }

        try Task.checkCancellation()
        let prs = measured("HistoryBuildPRs") {
            PersonalRecordService.computePRs(sessions: sessions)
        }

        try Task.checkCancellation()
        let snapshot = measured("HistoryBuildTrainings") {
            HistorySnapshotBuilder.build(
                sessions: sessions,
                routines: routines,
                prCountBySession: prs.prCountBySession,
                referenceDate: referenceDate
            )
        }
        try Task.checkCancellation()
        return snapshot
    }

    func fetchFortschrittSnapshot() async throws -> [FortschrittExerciseModel] {
        try Task.checkCancellation()
        let sessions = try measured("HistoryFetchSessions") {
            try fetchCompletedSessions()
        }
        let exercises = try measured("HistoryFetchExercises") {
            try modelContext.fetch(FetchDescriptor<Exercise>())
        }

        try Task.checkCancellation()
        let result = measured("HistoryBuildFortschritt") {
            FortschrittAggregator.build(sessions: sessions, liveExercises: exercises)
        }
        try Task.checkCancellation()
        return result
    }

    func fetchPRDetails(
        sessionID: UUID
    ) async throws -> [UUID: PersonalRecordService.PRDetail] {
        try Task.checkCancellation()
        let sessions = try measured("HistoryFetchSessions") {
            try fetchCompletedSessions()
        }
        try Task.checkCancellation()
        let prs = measured("HistoryBuildPRs") {
            PersonalRecordService.computePRs(sessions: sessions)
        }
        try Task.checkCancellation()
        return prs.prDetailsBySession[sessionID] ?? [:]
    }

    private func fetchCompletedSessions() throws -> [WorkoutSession] {
        // Fetching the child entity directly is the only way to prefetch the second to-many hop:
        // `WorkoutSession.workoutExercises` is a collection, so a key path cannot continue to
        // `.sets`. Registering the graph in this context prevents a set fault per exercise later.
        var exerciseDescriptor = FetchDescriptor<WorkoutExercise>(
            predicate: #Predicate { exercise in
                exercise.workoutSession?.endTime != nil
            }
        )
        exerciseDescriptor.relationshipKeyPathsForPrefetching = [\.sets, \.workoutSession]
        _ = try modelContext.fetch(exerciseDescriptor)

        var sessionDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.endTime != nil
            },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        sessionDescriptor.relationshipKeyPathsForPrefetching = [\.workoutExercises]
        return try modelContext.fetch(sessionDescriptor)
    }

    private func measured<Result>(
        _ name: StaticString,
        operation: () throws -> Result
    ) rethrows -> Result {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try operation()
    }
}
