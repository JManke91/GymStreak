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

    private func makePartialFailure(containing inner: CKError) -> CKError {
        CKError(
            .partialFailure,
            userInfo: [CKPartialErrorsByItemIDKey: [CKRecord.ID(recordName: "rec"): inner]]
        )
    }
}
