//
//  WatchSyncServicing.swift
//  GymStreak
//
//  What the Presentation layer needs from WatchConnectivityManager. Lets
//  ViewModels depend on a protocol instead of the concrete WatchConnectivity
//  singleton (which must still exist as `WatchConnectivityManager.shared` so
//  its WCSession delegate is registered at app launch).
//

import Foundation

@MainActor
protocol WatchSyncServicing: AnyObject {
    /// True while WatchConnectivity may still be holding watch content it has
    /// received but not yet delivered to our delegate.
    var mayHaveUndeliveredContent: Bool { get }

    /// Workouts received from the watch but not yet committed to SwiftData,
    /// mapped to the Domain ingestion model (the Data layer converts from its
    /// WatchConnectivity wire DTO at the boundary).
    func pendingWorkouts() -> [IncomingWatchWorkout]
    /// Removes a workout from the persistent pending buffer after it has been saved.
    func markPendingProcessed(id: UUID)
    /// Confirms to the watch that a completed workout has been persisted.
    func acknowledgeWorkoutSaved(id: UUID)
    /// Pushes the current routine list to the watch.
    func syncRoutines(_ routines: [Routine])
}
