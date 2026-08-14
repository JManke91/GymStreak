//
//  SyncEventSummary.swift
//  GymStreak
//
//  The Sendable boundary value for CloudKit mirroring events. Extracted from
//  CloudKitSyncStatusMonitor so that file stays under the 300-line limit.
//

import CloudKit
import CoreData
import Foundation

/// The `Sendable` projection of an `NSPersistentCloudKitContainer.Event`.
///
/// The event itself is a non-`Sendable` class delivered to a nonisolated
/// notification handler, so it must not cross into main-actor code. Everything
/// the state machine needs is extracted at that boundary into this value —
/// including the account-problem classification, which is the only thing the
/// non-`Sendable` `CKError` was needed for.
struct SyncEventSummary: Sendable {
    let identifier: UUID
    let type: NSPersistentCloudKitContainer.EventType
    let endDate: Date?
    let succeeded: Bool
    /// `true` when the failure indicates the iCloud account itself changed
    /// (not authenticated, managed-account restricted, permission failure).
    let isAccountProblem: Bool
    /// Debug-only rendering of the event's error, if any.
    let errorDescription: String?

    init(_ event: NSPersistentCloudKitContainer.Event) {
        identifier = event.identifier
        type = event.type
        endDate = event.endDate
        succeeded = event.succeeded
        errorDescription = event.error.map { String(describing: $0) }
        if let ckError = event.error as? CKError {
            switch ckError.code {
            case .notAuthenticated, .managedAccountRestricted, .permissionFailure:
                isAccountProblem = true
            default:
                isAccountProblem = false
            }
        } else {
            isAccountProblem = false
        }
    }
}
