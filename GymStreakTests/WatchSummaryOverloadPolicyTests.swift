//
//  WatchSummaryOverloadPolicyTests.swift
//  GymStreakTests
//
//  Ticket 05 (progressive-overload resurface): applying the weight increase
//  from the Watch's POST-WORKOUT RECAP, after the completed workout is frozen
//  and possibly already transferred or ingested. See
//  `WatchSummaryOverloadPolicyTests.swift` for the shared row state machine,
//  `WatchSummaryOverloadWireTests.swift` for the wire correlation and outgoing
//  ordering, and `WatchSummaryOverloadReceiveTests.swift` for the iOS side.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

// MARK: - Recap row state machine

@Suite(.serialized)
@MainActor
struct WatchSummaryOverloadPolicyTests {

    private func applied(
        probeWeight: Double = 62.5,
        newWeight: Double? = 62.5,
        isAssistance: Bool = false
    ) -> WatchAppliedOverload {
        WatchAppliedOverload(
            transactionID: UUID(), probeSetID: UUID(), probeWeight: probeWeight,
            newWeight: newWeight, targetRepMin: 8, isAssistance: isAssistance
        )
    }

    @Test
    func aQualifyingUnappliedExerciseIsActionable() {
        let state = WatchSummaryOverloadPolicy.state(
            applied: nil, isTransactionPending: false, currentProbeWeight: nil,
            qualifies: true, isTargetResolvable: true
        )
        #expect(state == .actionable)
    }

    @Test
    func anExerciseThatNeverQualifiedGetsNoRow() {
        let state = WatchSummaryOverloadPolicy.state(
            applied: nil, isTransactionPending: false, currentProbeWeight: nil,
            qualifies: false, isTargetResolvable: true
        )
        #expect(state == nil)
    }

    @Test
    func anUnresolvableTargetGetsNoActionableRow() {
        // Offering an increase that cannot be applied would fail on tap.
        let state = WatchSummaryOverloadPolicy.state(
            applied: nil, isTransactionPending: false, currentProbeWeight: nil,
            qualifies: true, isTargetResolvable: false
        )
        #expect(state == nil)
    }

    /// Applying mid-workout must reach the recap already confirmed — the whole
    /// point of keeping one applied record for both surfaces.
    @Test
    func anAlreadyAppliedExerciseIsConfirmedNotActionable() {
        let state = WatchSummaryOverloadPolicy.state(
            applied: applied(), isTransactionPending: true, currentProbeWeight: 62.5,
            qualifies: true, isTargetResolvable: true
        )
        #expect(state == .applied(newWeight: 62.5, isAssistance: false))
    }

    @Test
    func aPendingOfflineApplyIsConfirmedNeverSuperseded() {
        // The iPhone has not ruled on it. Reporting a conflict here would be a
        // lie, and reverting to an Apply button would invite a double increase.
        let state = WatchSummaryOverloadPolicy.state(
            applied: applied(), isTransactionPending: true, currentProbeWeight: 60,
            qualifies: true, isTargetResolvable: true
        )
        #expect(state == .applied(newWeight: 62.5, isAssistance: false))
    }

    @Test
    func aRetiredTransactionWhoseValueSurvivedStaysConfirmed() {
        let state = WatchSummaryOverloadPolicy.state(
            applied: applied(), isTransactionPending: false, currentProbeWeight: 62.5,
            qualifies: true, isTargetResolvable: true
        )
        #expect(state == .applied(newWeight: 62.5, isAssistance: false))
    }

    @Test
    func aRetiredTransactionOverriddenOnTheIPhoneReadsAsSuperseded() {
        let state = WatchSummaryOverloadPolicy.state(
            applied: applied(), isTransactionPending: false, currentProbeWeight: 70,
            qualifies: true, isTargetResolvable: true
        )
        #expect(state == .superseded)
    }

    @Test
    func aSupersededRowNeverReturnsToActionable() {
        // The hard requirement: whatever iOS decides, an applied row must not
        // silently become a fresh Apply button.
        for pending in [true, false] {
            for probe in [nil, 60, 62.5, 70] as [Double?] {
                let state = WatchSummaryOverloadPolicy.state(
                    applied: applied(), isTransactionPending: pending, currentProbeWeight: probe,
                    qualifies: true, isTargetResolvable: true
                )
                #expect(state != .actionable)
                #expect(state != nil)
            }
        }
    }

    @Test
    func aDeletedTargetKeepsTheConfirmedStateRatherThanInventingAConflict() {
        // The increase may well have applied before the slot was deleted.
        let state = WatchSummaryOverloadPolicy.state(
            applied: applied(), isTransactionPending: false, currentProbeWeight: nil,
            qualifies: false, isTargetResolvable: false
        )
        #expect(state == .applied(newWeight: 62.5, isAssistance: false))
    }

    @Test
    func aNonuniformSchemeCarriesNoSingleWeight() {
        // Naming the first set's result would misstate every other set.
        let state = WatchSummaryOverloadPolicy.state(
            applied: applied(newWeight: nil), isTransactionPending: true,
            currentProbeWeight: 62.5, qualifies: true, isTargetResolvable: true
        )
        #expect(state == .applied(newWeight: nil, isAssistance: false))
    }

    @Test
    func assistanceDirectionSurvivesIntoTheRow() {
        let state = WatchSummaryOverloadPolicy.state(
            applied: applied(probeWeight: 17.5, newWeight: 17.5, isAssistance: true),
            isTransactionPending: true, currentProbeWeight: 17.5,
            qualifies: true, isTargetResolvable: true
        )
        #expect(state == .applied(newWeight: 17.5, isAssistance: true))
    }

    /// A JSON round trip can leave a weight a last bit off; that must not read
    /// as the iPhone having overridden the value.
    @Test
    func floatDriftIsNotAConflict() {
        let state = WatchSummaryOverloadPolicy.state(
            applied: applied(), isTransactionPending: false, currentProbeWeight: 62.500_02,
            qualifies: true, isTargetResolvable: true
        )
        #expect(state == .applied(newWeight: 62.5, isAssistance: false))
    }
}
