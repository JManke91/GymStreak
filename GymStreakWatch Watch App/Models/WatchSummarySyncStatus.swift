//
//  WatchSummarySyncStatus.swift
//  GymStreakWatch Watch App
//
//  What the post-workout summary tells the user about their workout reaching
//  the iPhone (docs/watch-sync.md, "Showing the guarantee on the summary").
//  Derived only from the workout's HISTORY entry in the durable outgoing queue:
//  a split template intent is a separate entry and never makes a saved workout
//  look unsaved — template failures have their own notice.
//

import Foundation

enum WatchSummarySyncStatus: Equatable {
    /// Queued, not yet acknowledged, and the iPhone is reachable.
    case saving
    /// Queued and the iPhone is out of reach. Reassurance, not an error: the
    /// entry is durable and is sent on the next lifecycle trigger.
    case waitingForPhone
    /// The iPhone's terminal acknowledgment retired the history entry.
    case saved
    /// The history entry's bytes were quarantined and will never transport.
    case notSent

    /// - Parameter historyPhase: the phase of the workout's history entry, or
    ///   nil once it has been retired. Only meaningful after the workout was
    ///   durably enqueued — the summary never appears before that.
    static func resolve(historyPhase: OutgoingWorkoutPhase?, isPhoneReachable: Bool) -> Self {
        switch historyPhase {
        case nil: .saved
        case .quarantined: .notSent
        case .awaitingHealthKitMetadata, .awaitingHealthKitFinish, .transportEligible:
            isPhoneReachable ? .saving : .waitingForPhone
        }
    }
}
