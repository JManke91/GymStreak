//
//  WorkoutRecoveryReconcilerTests.swift
//  GymStreakTests
//
//  The conservative recovery policy (ticket 09 of in-workout routine editing):
//  history/receipt resolves, duplicate-external-UUID conflict, inbox-in-flight
//  and hasContentPending positive-only postpones, grace-period boundary, the
//  user-confirmed offer, and the debug summary states — including that unknown
//  remote progress is never inferred from a false hasContentPending.
//

import Foundation
import Testing
@testable import GymStreak

struct WorkoutRecoveryReconcilerTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func makeEntry(
        discoveredAt: Date? = nil,
        objectUUIDs: Set<UUID> = [UUID()],
        state: WorkoutRecoveryState = .provisional,
        lastError: String? = nil
    ) -> WorkoutRecoveryLedgerEntry {
        WorkoutRecoveryLedgerEntry(
            externalUUID: UUID(),
            healthKitObjectUUIDs: objectUUIDs,
            startDate: base,
            endDate: base.addingTimeInterval(3600),
            routineName: "Push",
            fromWatch: true,
            discoveredAt: discoveredAt ?? base,
            lastError: lastError,
            state: state
        )
    }

    private func context(
        history: Bool = false,
        inbox: Bool = false,
        wcPending: Bool = false,
        grace: TimeInterval = 60,
        now: Date? = nil
    ) -> RecoveryReconciliationContext {
        RecoveryReconciliationContext(
            hasCommittedHistoryOrReceipt: history,
            isBufferedOrDraining: inbox,
            watchConnectivityMayDeliver: wcPending,
            gracePeriod: grace,
            now: now ?? base
        )
    }

    // MARK: - decide

    @Test
    func historyOrReceiptResolvesRegardlessOfEverythingElse() {
        let e = makeEntry(objectUUIDs: [UUID(), UUID()]) // even a conflict
        let decision = WorkoutRecoveryReconciler.decide(
            for: e, context: context(history: true, inbox: true, wcPending: true)
        )
        #expect(decision == .resolve)
    }

    @Test
    func duplicateExternalUUIDIsAConflictNotAnOffer() {
        let e = makeEntry(discoveredAt: base, objectUUIDs: [UUID(), UUID()])
        // Past grace, nothing pending — would otherwise be an offer.
        let decision = WorkoutRecoveryReconciler.decide(
            for: e, context: context(now: base.addingTimeInterval(120))
        )
        #expect(decision == .conflict)
    }

    @Test
    func inboxInFlightPostpones() {
        let decision = WorkoutRecoveryReconciler.decide(
            for: makeEntry(), context: context(inbox: true, now: base.addingTimeInterval(120))
        )
        #expect(decision == .postpone(.inboxInFlight))
    }

    @Test
    func hasContentPendingTrueIsPositiveEvidenceToPostpone() {
        let decision = WorkoutRecoveryReconciler.decide(
            for: makeEntry(), context: context(wcPending: true, now: base.addingTimeInterval(120))
        )
        #expect(decision == .postpone(.watchConnectivityPending))
    }

    @Test
    func withinGracePeriodPostpones() {
        let decision = WorkoutRecoveryReconciler.decide(
            for: makeEntry(discoveredAt: base), context: context(now: base.addingTimeInterval(30))
        )
        #expect(decision == .postpone(.withinGracePeriod))
    }

    @Test
    func offersOnlyAfterGraceWithNoPendingEvidence() {
        // hasContentPending == false plus grace elapsed → an offer, but never an
        // automatic reconstruction (the caller still requires user confirmation).
        let decision = WorkoutRecoveryReconciler.decide(
            for: makeEntry(discoveredAt: base),
            context: context(wcPending: false, now: base.addingTimeInterval(61))
        )
        #expect(decision == .offerRecovery)
    }

    @Test
    func placeholderSavedIsNeverOfferedAgain() {
        let decision = WorkoutRecoveryReconciler.decide(
            for: makeEntry(state: .placeholderSaved),
            context: context(now: base.addingTimeInterval(600))
        )
        #expect(decision == .resolve)
    }

    @Test
    func terminalStatesResolve() {
        for state in [WorkoutRecoveryState.resolvedByHistory, .placeholderReplaced, .tombstoned] {
            let decision = WorkoutRecoveryReconciler.decide(
                for: makeEntry(state: state), context: context()
            )
            #expect(decision == .resolve)
        }
    }

    // MARK: - summaryState

    @Test
    func summaryUnknownWithinGraceNeverInferredFromFalseContentPending() {
        let state = WorkoutRecoveryReconciler.summaryState(
            for: makeEntry(discoveredAt: base),
            context: context(wcPending: false, now: base.addingTimeInterval(10))
        )
        #expect(state == .unknown)
    }

    @Test
    func summaryHealthKitOnlyAfterGrace() {
        let state = WorkoutRecoveryReconciler.summaryState(
            for: makeEntry(discoveredAt: base), context: context(now: base.addingTimeInterval(120))
        )
        #expect(state == .healthKitOnlyCandidate)
    }

    @Test
    func summaryDistinguishesInboxedFromDeferred() {
        let inboxed = WorkoutRecoveryReconciler.summaryState(
            for: makeEntry(), context: context(inbox: true)
        )
        #expect(inboxed == .receivedInboxed)

        let deferred = WorkoutRecoveryReconciler.summaryState(
            for: makeEntry(lastError: "save failed"), context: context(inbox: true)
        )
        #expect(deferred == .ingestDeferred)
    }

    @Test
    func summaryOutstandingTransportOnContentPending() {
        let state = WorkoutRecoveryReconciler.summaryState(
            for: makeEntry(), context: context(wcPending: true)
        )
        #expect(state == .outstandingTransport)
    }

    @Test
    func summaryReflectsTerminalAndPlaceholderStates() {
        #expect(WorkoutRecoveryReconciler.summaryState(
            for: makeEntry(state: .placeholderSaved), context: context()) == .placeholder)
        #expect(WorkoutRecoveryReconciler.summaryState(
            for: makeEntry(state: .placeholderReplaced), context: context()) == .placeholderReplaced)
        #expect(WorkoutRecoveryReconciler.summaryState(
            for: makeEntry(state: .resolvedByHistory), context: context()) == .historyCommitted)
        #expect(WorkoutRecoveryReconciler.summaryState(
            for: makeEntry(objectUUIDs: [UUID(), UUID()]), context: context()) == .conflict)
    }
}
