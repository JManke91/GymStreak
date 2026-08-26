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
    /// `true` when the failure will not heal on its own — a schema mismatch, a
    /// rejected request, a full account. Separates a genuinely broken sync from
    /// the transient failures (`.waiting`) that CloudKit retries by itself.
    let isPersistentFailure: Bool
    /// Rendering of the event's error, if any. Logged on failure, so a broken
    /// sync leaves a trace in the device log rather than only in a debug build.
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
        isPersistentFailure = Self.isPersistentFailure(event.error)
    }

    /// Classifies a mirroring error as "a retry cannot fix this".
    ///
    /// Extracted as a static function on the error rather than folded into the
    /// initializer because `NSPersistentCloudKitContainer.Event` cannot be
    /// constructed in a test, and this classification is the part worth testing.
    ///
    /// Deliberately conservative: anything that is not a `CKError` — and every
    /// `CKError` not listed here (network loss, rate limiting, zone busy,
    /// service unavailable, a record conflict) — stays transient, because a
    /// false "sync is broken" is worse than a late one. The listed codes are the
    /// ones a missing record type or a schema drift raises, which is the failure
    /// that hid the plan-mirroring bug (see docs/workout-planning.md).
    static func isPersistentFailure(_ error: Error?) -> Bool {
        guard let ckError = error as? CKError else { return false }
        if ckError.code == .partialFailure {
            guard let partials = ckError.partialErrorsByItemID else { return false }
            return partials.values.contains { isPersistentFailure($0) }
        }
        switch ckError.code {
        case .invalidArguments,
             .serverRejectedRequest,
             .unknownItem,
             .constraintViolation,
             .incompatibleVersion,
             .badContainer,
             .badDatabase,
             .missingEntitlement,
             .quotaExceeded:
            return true
        default:
            return false
        }
    }
}
