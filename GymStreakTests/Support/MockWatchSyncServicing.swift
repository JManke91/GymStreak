//
//  MockWatchSyncServicing.swift
//  GymStreakTests
//
//  Test double for WatchSyncServicing that records calls instead of talking to
//  WatchConnectivity, so RoutinesViewModel can be constructed in isolation.
//

import Foundation
@testable import GymStreak

@MainActor
final class MockWatchSyncServicing: WatchSyncServicing, WatchRoutineSnapshotTransporting {
    var mayHaveUndeliveredContent: Bool = false
    var pendingWorkoutsQueue: [IncomingWatchWorkout] = []

    private(set) var acknowledgeWorkoutSavedCalls: [UUID] = []
    private(set) var syncRoutinesCalls: [[Routine]] = []
    private(set) var syncRoutineSnapshotCalls: [[WatchRoutine]] = []
    private(set) var syncExerciseCatalogCalls: [[Exercise]] = []
    private(set) var stageAuthoritativeRoutineSnapshotCalls: [[WatchRoutine]] = []
    private(set) var templateAcks: [WatchTemplateTransactionAck] = []

    /// The version `stageAuthoritativeRoutineSnapshot` reports. nil simulates "no
    /// routine authority established yet" (no watch challenge received).
    var stagedRoutineVersion: (epoch: UUID, generation: UInt64)? = (UUID(), 1)
    var watchRoutineChallenge: (epoch: UUID?, generation: UInt64)?

    func pendingWorkouts() -> [IncomingWatchWorkout] {
        pendingWorkoutsQueue
    }

    func acknowledgeWorkoutSaved(id: UUID) {
        acknowledgeWorkoutSavedCalls.append(id)
    }

    func syncRoutines(_ routines: [Routine]) {
        syncRoutinesCalls.append(routines)
    }

    func syncRoutineSnapshot(_ routines: [WatchRoutine]) {
        syncRoutineSnapshotCalls.append(routines)
    }

    func stageAuthoritativeRoutineSnapshot(
        _ routines: [WatchRoutine]
    ) -> (epoch: UUID, generation: UInt64)? {
        stageAuthoritativeRoutineSnapshotCalls.append(routines)
        guard let version = stagedRoutineVersion else { return nil }
        // Each staged snapshot gets its own generation, mirroring the real
        // authority's monotonic counter.
        stagedRoutineVersion = (version.epoch, version.generation + 1)
        return version
    }

    func acknowledgeTemplateTransaction(_ ack: WatchTemplateTransactionAck) {
        templateAcks.append(ack)
    }

    func syncExerciseCatalog(_ exercises: [Exercise]) {
        syncExerciseCatalogCalls.append(exercises)
    }
}
