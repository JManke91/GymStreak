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
///
/// **CloudKit reports per-zone failures as a `.partialFailure` wrapper**, so
/// every classification here has to look one level down — though the event the
/// app receives may have been stripped of those per-item errors before it
/// arrives, in which case no classification can know the reason. See §4.2b of
/// docs/settings-tab.md, which records the measurements.
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
        errorDescription = event.error.map(Self.describe)
        isAccountProblem = Self.isAccountProblem(event.error)
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
        inspect(error) { code in
            switch code {
            case .invalidArguments,
                 .serverRejectedRequest,
                 .unknownItem,
                 .constraintViolation,
                 .incompatibleVersion,
                 .badContainer,
                 .badDatabase,
                 .missingEntitlement,
                 .quotaExceeded:
                true
            default:
                false
            }
        }
    }

    /// Classifies a mirroring error as "the iCloud account is the problem",
    /// which makes the monitor re-query `CKContainer.accountStatus()`.
    static func isAccountProblem(_ error: Error?) -> Bool {
        inspect(error) { code in
            switch code {
            case .notAuthenticated, .managedAccountRestricted, .permissionFailure:
                true
            default:
                false
            }
        }
    }

    /// Renders a mirroring error as the CloudKit codes it contains, followed by
    /// the error's own description verbatim.
    ///
    /// **Only ever adds.** `NSError.description` is accurate — it does print
    /// `userInfo`, so a wrapped reason, a `ServerErrorDescription` and a
    /// `CKRetryAfter` are all in there (measured, 2026-09-03) — but a
    /// `.partialFailure` puts the code that matters inside a nested,
    /// quote-escaped dictionary that can hold one entry per record of a bulk
    /// import. The prefix lifts those codes out as one greppable token
    /// (`CKError [2 (1), 21 (37)]`), and nothing is dropped, so this can only be
    /// more informative than the `String(describing:)` it wraps. A non-`CKError`
    /// error is passed straight through.
    ///
    /// It therefore **inherits** that description's size: ~7 KB for 50 per-item
    /// errors, ~283 KB for 2,000 (measured), built on the main actor and logged
    /// in one line. The tally adds ~26 bytes to that rather than replacing it —
    /// see the follow-up in §9 of docs/settings-tab.md.
    ///
    /// Codes are numbers, not Swift case names: `CKError.Code` is an imported
    /// `NS_ENUM` whose `String(describing:)` is the useless
    /// `CKErrorCode(rawValue: 2)`, and numbers are what CloudKit's own lines
    /// speak anyway (`"Change Token Expired" (21/2026)`). The tally reaches the
    /// same errors the verdicts do — those under `partialErrorsByItemID`, not one
    /// nested at `NSUnderlyingErrorKey` — so the log can never name a code the
    /// verdict did not weigh.
    static func describe(_ error: Error) -> String {
        var counts: [Int: Int] = [:]
        countCKErrorCodes(in: error, into: &counts)
        guard !counts.isEmpty else { return String(describing: error) }
        let summary = counts
            .sorted { $0.key < $1.key }
            .map { "\($0.key) (\($0.value))" }
            .joined(separator: ", ")
        return "CKError [\(summary)] \(String(describing: error))"
    }

    /// Tallies the `CKError` codes `error` carries — its own, plus each error
    /// under `partialErrorsByItemID`. Counted rather than listed per item,
    /// because one `.partialFailure` of a bulk import can carry hundreds of
    /// identical per-record errors and a tally of them stays one short token.
    ///
    /// Descends on the same condition as `inspect(_:matches:)`, deliberately: if
    /// the two disagreed about when to look inside, the prefix could name a code
    /// the verdict never weighed, and the log would contradict the row.
    private static func countCKErrorCodes(in error: Error, into counts: inout [Int: Int]) {
        guard let ckError = error as? CKError else { return }
        counts[ckError.code.rawValue, default: 0] += 1
        guard ckError.code == .partialFailure else { return }
        for nested in ckError.partialErrorsByItemID?.values ?? [:].values {
            countCKErrorCodes(in: nested, into: &counts)
        }
    }

    /// Runs `matches` against the error's `CKError` code, and — because CloudKit
    /// wraps per-zone failures — against the code of every error nested in a
    /// `.partialFailure`. Non-`CKError` errors match nothing.
    private static func inspect(
        _ error: Error?,
        matches: (CKError.Code) -> Bool
    ) -> Bool {
        guard let ckError = error as? CKError else { return false }
        if ckError.code == .partialFailure {
            guard let partials = ckError.partialErrorsByItemID else { return false }
            return partials.values.contains { inspect($0, matches: matches) }
        }
        return matches(ckError.code)
    }
}
