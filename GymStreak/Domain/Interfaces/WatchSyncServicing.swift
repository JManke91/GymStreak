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

/// Terminal decision for a requested watch template transaction (ticket 05).
/// `applied` — the complete requested transaction committed (or was already
/// reconciled idempotently). `rejected` — a deliberate terminal decision left
/// the routine byte-for-byte untouched. Transient failures are neither: they
/// send no terminal acknowledgment at all.
enum TemplateTransactionOutcome: String, Codable, Sendable {
    case applied
    case rejected
}

/// Versioned terminal acknowledgment for a watch template transaction: the
/// outcome plus the authoritative routine generation staged for the watch.
/// The watch retires the transaction only once it has both received this ack
/// and applied the referenced routine epoch/generation.
struct WatchTemplateTransactionAck {
    let workoutId: UUID?
    let transactionID: UUID
    let outcome: TemplateTransactionOutcome
    let senderEpoch: UUID
    let sequence: UInt64
    let routineEpoch: UUID
    let routineGeneration: UInt64
}

@MainActor
protocol WatchSyncServicing: AnyObject {
    /// True while WatchConnectivity may still be holding watch content it has
    /// received but not yet delivered to our delegate.
    var mayHaveUndeliveredContent: Bool { get }

    /// Workouts received from the watch but not yet committed to SwiftData,
    /// mapped to the Domain ingestion model (the Data layer converts from its
    /// WatchConnectivity wire DTO at the boundary). Read-only: the durable
    /// inbox is drained and pruned by the ingestion coordinator, not by
    /// Presentation consumers.
    func pendingWorkouts() -> [IncomingWatchWorkout]
    /// Confirms to the watch that a completed workout has been persisted.
    func acknowledgeWorkoutSaved(id: UUID)
    /// Pushes the current routine list to the watch.
    func syncRoutines(_ routines: [Routine])
    /// Sends the versioned terminal acknowledgment for a template transaction.
    func acknowledgeTemplateTransaction(_ ack: WatchTemplateTransactionAck)
    /// The watch's last published routine authority challenge: its accepted
    /// epoch (nil before bootstrap) and generation high-water. Restored from
    /// persisted state at launch, so it may be non-nil before this process has
    /// received any context — and may be stale until the watch republishes.
    /// nil only when no challenge has ever been received on this install.
    var watchRoutineChallenge: (epoch: UUID?, generation: UInt64)? { get }
    /// Stages a full snapshot of the exercise library for transfer to the
    /// watch. Safe to call anytime — content is staged durably and sent when
    /// the session/watch allows; identical content is suppressed.
    func syncExerciseCatalog(_ exercises: [Exercise])
}
