//
//  WorkoutRecoveryCoordinating.swift
//  GymStreak
//
//  What the Presentation layer needs from the HealthKit recovery engine
//  (ticket 09 of in-workout routine editing). ViewModels depend on this
//  protocol, never the concrete `WorkoutRecoveryCoordinator` (a Data type).
//
//  The engine owns incremental HealthKit discovery, the durable recovery
//  ledger, and the conservative reconciler; it publishes only the candidates
//  that have been CLEARED to offer for user-confirmed recovery. It posts
//  `.recoverableWorkoutsDidChange` when that set changes so observers refresh.
//

import Foundation

extension Notification.Name {
    /// Posted after the recovery engine republishes its recoverable set.
    static let recoverableWorkoutsDidChange = Notification.Name("recoverableWorkoutsDidChange")
}

@MainActor
protocol WorkoutRecoveryCoordinating: AnyObject {
    /// Candidates the reconciler has cleared for user-confirmed, history-only
    /// recovery (grace elapsed, nothing pending, no conflict, not already
    /// ingested). Never auto-recovered — the UI must still confirm.
    var recoverableWorkouts: [OrphanedWorkout] { get }

    /// Runs a fresh incremental HealthKit anchored drain, applies it to the
    /// ledger, then reconciles. Called at launch and on foreground.
    func refresh()

    /// Re-evaluates existing candidates against current sync facts WITHOUT a
    /// new HealthKit drain. Called when the inbox, a terminal receipt/history
    /// commit, or WatchConnectivity state changes.
    func reconcile()

    /// Records that a user-confirmed, history-only placeholder was saved for a
    /// candidate, so a later rich payload (materialized under a different
    /// session id by the ingestion path) is detectable as a replacement.
    func markPlaceholderSaved(externalUUID: UUID, sessionId: UUID)

    /// A bounded, privacy-conscious support summary — one line per candidate
    /// describing its best-known pipeline position (unknown remote progress
    /// stays `unknown`, never inferred from a false `hasContentPending`).
    func debugSummary() -> [String]
}
