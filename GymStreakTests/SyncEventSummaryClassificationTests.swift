//
//  SyncEventSummaryClassificationTests.swift
//  GymStreakTests
//
//  The one part of the mirroring-failure path that can be tested without
//  CloudKit: deciding whether a failed export is transient (retried by CloudKit,
//  row stays "Waiting") or permanent (row goes to "Error"). Getting this wrong in
//  either direction is what the ticket exists to prevent — a false "broken" cries
//  wolf, a false "waiting" is the silence that hid the plan-mirroring bug.
//  See docs/settings-tab.md §4.2.
//

import CloudKit
import Foundation
import Testing
@testable import GymStreak

@Suite
struct SyncEventSummaryClassificationTests {

    @Test("A schema-shaped rejection is permanent")
    func schemaRejectionIsPersistent() {
        for code in [CKError.Code.invalidArguments, .serverRejectedRequest, .unknownItem] {
            #expect(SyncEventSummary.isPersistentFailure(CKError(code)))
        }
    }

    @Test("Network and rate-limit failures stay transient")
    func transientFailuresAreNotPersistent() {
        for code in [
            CKError.Code.networkFailure,
            .networkUnavailable,
            .serviceUnavailable,
            .requestRateLimited,
            .zoneBusy,
            .serverRecordChanged
        ] {
            #expect(SyncEventSummary.isPersistentFailure(CKError(code)) == false)
        }
    }

    @Test("No error, and a non-CloudKit error, are never permanent")
    func nonCloudKitErrorsAreNotPersistent() {
        #expect(SyncEventSummary.isPersistentFailure(nil) == false)
        #expect(
            SyncEventSummary.isPersistentFailure(
                NSError(domain: NSCocoaErrorDomain, code: 134_060)
            ) == false
        )
    }

    @Test("A partial failure is judged by the errors it contains")
    func partialFailureInspectsItsParts() {
        #expect(
            SyncEventSummary.isPersistentFailure(
                makePartialFailure(containing: CKError(.unknownItem))
            )
        )
        #expect(
            SyncEventSummary.isPersistentFailure(
                makePartialFailure(containing: CKError(.networkFailure))
            ) == false
        )
        // An empty partial failure carries no evidence of anything permanent.
        #expect(SyncEventSummary.isPersistentFailure(CKError(.partialFailure)) == false)
    }

    @Test("An account failure is found inside a partial failure too")
    func accountProblemInspectsPartialFailure() {
        #expect(SyncEventSummary.isAccountProblem(CKError(.notAuthenticated)))
        #expect(
            SyncEventSummary.isAccountProblem(
                makePartialFailure(containing: CKError(.managedAccountRestricted))
            )
        )
        #expect(SyncEventSummary.isAccountProblem(CKError(.networkFailure)) == false)
        #expect(SyncEventSummary.isAccountProblem(nil) == false)
    }

    @Test("An account problem is transient by verdict, which is why it is logged apart")
    func accountProblemIsNotAPersistentFailure() {
        // Load-bearing for `log(_:)`: CloudKit does keep retrying these, so the
        // persistent verdict is `false` — but a retry cannot fix a signed-out
        // account, so the log needs its own `.error` branch for the class rather
        // than letting it fall into "CloudKit retries".
        for code in [CKError.Code.notAuthenticated, .permissionFailure, .managedAccountRestricted] {
            #expect(SyncEventSummary.isAccountProblem(CKError(code)))
            #expect(SyncEventSummary.isPersistentFailure(CKError(code)) == false)
        }
    }

    @Test("The description lifts every nested code out of the wrapper")
    func descriptionSummarisesNestedCodes() {
        let description = SyncEventSummary.describe(
            makePartialFailure(containing: CKError(.changeTokenExpired))
        )
        // The wrapper alone (`Code=2`) is what made the device log unreadable;
        // 21 — change-token expiry — is the code that explains it.
        #expect(description.hasPrefix("CKError [2 (1), 21 (1)]"))
        // And it only ever adds: `NSError.description` does print `userInfo`, so
        // the server's own explanation and any retry hint must survive verbatim.
        #expect(description.contains("Error Domain=CKErrorDomain Code=2"))
        #expect(description.contains("recordName=rec"))
    }

    @Test("Identical per-record failures are counted, not listed")
    func descriptionCountsRepeatedCodes() {
        // One partial failure of a bulk import can carry hundreds of these, and
        // the string is built on the main actor and logged in a single line.
        let partials = Dictionary(
            uniqueKeysWithValues: (0..<50).map { index in
                (CKRecord.ID(recordName: "rec-\(index)") as AnyHashable, CKError(.unknownItem) as Error)
            }
        )
        let description = SyncEventSummary.describe(
            CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: partials])
        )
        #expect(description.hasPrefix("CKError [2 (1), 11 (50)]"))
    }

    @Test("A non-CloudKit error is passed through untouched")
    func descriptionPassesThroughForeignErrors() {
        let error = NSError(domain: NSCocoaErrorDomain, code: 134_060)
        #expect(SyncEventSummary.describe(error) == String(describing: error))
    }

    private func makePartialFailure(containing inner: CKError) -> CKError {
        CKError(
            .partialFailure,
            userInfo: [CKPartialErrorsByItemIDKey: [CKRecord.ID(recordName: "rec"): inner]]
        )
    }
}
