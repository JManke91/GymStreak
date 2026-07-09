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
final class MockWatchSyncServicing: WatchSyncServicing {
    var mayHaveUndeliveredContent: Bool = false
    var pendingWorkoutsQueue: [IncomingWatchWorkout] = []

    private(set) var markPendingProcessedCalls: [UUID] = []
    private(set) var acknowledgeWorkoutSavedCalls: [UUID] = []
    private(set) var syncRoutinesCalls: [[Routine]] = []

    func pendingWorkouts() -> [IncomingWatchWorkout] {
        pendingWorkoutsQueue
    }

    func markPendingProcessed(id: UUID) {
        markPendingProcessedCalls.append(id)
    }

    func acknowledgeWorkoutSaved(id: UUID) {
        acknowledgeWorkoutSavedCalls.append(id)
    }

    func syncRoutines(_ routines: [Routine]) {
        syncRoutinesCalls.append(routines)
    }
}
