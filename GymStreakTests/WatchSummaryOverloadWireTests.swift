//
//  WatchSummaryOverloadWireTests.swift
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

// MARK: - Wire correlation + outgoing ordering

@Suite(.serialized)
@MainActor
struct WatchSummaryOverloadWireTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures

    private func intent(
        slotID: UUID = UUID(), setID: UUID = UUID(),
        sourceWorkoutID: UUID? = nil, sourceRoutineExerciseID: UUID? = nil
    ) -> WatchProgressiveOverloadIntent {
        var intent = WatchProgressiveOverloadIntent(
            routineExerciseID: slotID, alternativeID: nil, targetRepMin: 8,
            setChanges: [WatchTemplateSetChange(
                setID: setID, expectedReps: 12, expectedWeight: 60,
                proposedReps: 8, proposedWeight: 62.5
            )]
        )
        intent.sourceWorkoutID = sourceWorkoutID
        intent.sourceRoutineExerciseID = sourceRoutineExerciseID
        return intent
    }

    @Test
    func correlationRoundTripsThroughTheWireAndTheDomainMapper() throws {
        let workoutID = UUID(), slotID = UUID()
        let decoded = try JSONDecoder().decode(
            WatchProgressiveOverloadIntent.self,
            from: JSONEncoder().encode(
                intent(slotID: slotID, sourceWorkoutID: workoutID, sourceRoutineExerciseID: slotID)
            )
        )
        #expect(decoded.sourceWorkoutID == workoutID)
        #expect(decoded.sourceRoutineExerciseID == slotID)

        let mapped = decoded.toIncomingProgressiveOverload()
        #expect(mapped.sourceWorkout?.workoutID == workoutID)
        #expect(mapped.sourceWorkout?.routineExerciseID == slotID)
    }

    /// The verdict both surfaces read: the Watch recap decides whether to show
    /// a weight, and iOS History decides the same thing again from the
    /// delivered payload. `weightsMatch` is a non-transitive tolerance check, so
    /// the shared helper anchoring on the first set is what makes them agree —
    /// a pairwise loop could return different answers for the same intent.
    @Test
    func uniformityIsOneSharedVerdictAnchoredOnTheFirstSet() {
        func changes(_ weights: [Double]) -> [WatchTemplateSetChange] {
            weights.map {
                WatchTemplateSetChange(
                    setID: UUID(), expectedReps: 12, expectedWeight: 60,
                    proposedReps: 8, proposedWeight: $0
                )
            }
        }
        #expect(WatchTemplateSetChange.haveUniformProposedWeights(changes([62.5, 62.5, 62.5])))
        #expect(!WatchTemplateSetChange.haveUniformProposedWeights(changes([62.5, 65, 67.5])))
        // A JSON round trip's last-bit drift is not a pyramid scheme.
        #expect(WatchTemplateSetChange.haveUniformProposedWeights(changes([62.5, 62.500_02])))
        // Single set, and the degenerate empty case, are trivially uniform.
        #expect(WatchTemplateSetChange.haveUniformProposedWeights(changes([62.5])))
        #expect(WatchTemplateSetChange.haveUniformProposedWeights([]))
        // Drifting away from the ANCHOR is what counts — a chain of individually
        // in-tolerance steps must not read as uniform.
        #expect(!WatchTemplateSetChange.haveUniformProposedWeights(
            changes([62.5, 62.500_05, 62.500_1, 62.500_15, 62.500_2])
        ))
    }

    @Test
    func aMidWorkoutIntentCarriesNoCorrelation() {
        let mapped = intent().toIncomingProgressiveOverload()
        #expect(mapped.sourceWorkout == nil)
    }

    /// A ticket-04 payload predates the correlation keys entirely.
    @Test
    func aPayloadWithoutCorrelationKeysStillDecodes() throws {
        let json = """
        {
          "schemaVersion": 1,
          "routineExerciseID": "\(UUID().uuidString)",
          "targetRepMin": 8,
          "setChanges": [{
            "setID": "\(UUID().uuidString)", "expectedReps": 12, "expectedWeight": 60,
            "proposedReps": 8, "proposedWeight": 62.5
          }]
        }
        """
        let decoded = try JSONDecoder().decode(
            WatchProgressiveOverloadIntent.self, from: Data(json.utf8)
        )
        #expect(decoded.isWellFormed)
        #expect(decoded.sourceWorkoutID == nil)
        #expect(decoded.toIncomingProgressiveOverload().sourceWorkout == nil)
    }

    @Test(arguments: [true, false])
    func halfACorrelationIsMalformedAndMapsToNothing(_ workoutHalf: Bool) {
        let half = workoutHalf
            ? intent(sourceWorkoutID: UUID())
            : intent(sourceRoutineExerciseID: UUID())
        #expect(!half.isWellFormed)
        #expect(half.toIncomingProgressiveOverload().sourceWorkout == nil)
    }

    /// The recap's transaction takes the sequence AFTER the completed workout's
    /// template transaction, so the two share one per-routine ordering lane and
    /// the recap increase can never be replayed under the workout's writeback.
    @Test
    func aRecapOverloadFollowsTheCompletedWorkoutsTemplateTransaction() throws {
        let directory = try Fixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatchSyncStateStore(directory: directory)
        let routineID = UUID(), slotID = UUID()

        // The workout is frozen first — that is what makes the recap appear.
        let workout = Fixtures.makeWorkout(routineId: routineID, shouldUpdateTemplate: true)
        try store.enqueue(workout, phase: .awaitingHealthKitFinish)
        // Then the user applies from the recap.
        let overloadID = UUID()
        try store.enqueue(
            progressiveOverload: intent(
                slotID: slotID, sourceWorkoutID: workout.id, sourceRoutineExerciseID: slotID
            ),
            routineID: routineID, transactionID: overloadID
        )

        let workoutTemplate = try #require(Fixtures.templateEntry(in: store, forWorkout: workout.id))
        #expect(workoutTemplate.templateTransaction?.sequence == 0)
        let overloadEntry = try #require(store.all.first { $0.id == overloadID })
        #expect(overloadEntry.templateTransaction?.sequence == 1)
        // FIFO: the workout's template transaction owns the earlier sequence and
        // is the only eligible one. Since the history/template split it no longer
        // waits on HealthKit — only the workout's history half does.
        #expect(store.transportEligibleEntries().map(\.id) == [workoutTemplate.id])
        #expect(store.entry(id: workout.id)?.phase == .awaitingHealthKitFinish)
    }

    /// The reason the correlation cannot assume the workout arrives first: a
    /// history-only workout is not FIFO-gated, and while it waits on HealthKit
    /// the recap's transaction is already transport-eligible.
    @Test
    func aRecapOverloadCanReachTheIPhoneBeforeItsOwnWorkout() throws {
        let directory = try Fixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatchSyncStateStore(directory: directory)
        let routineID = UUID(), slotID = UUID(), overloadID = UUID()

        let workout = Fixtures.makeWorkout(routineId: routineID, shouldUpdateTemplate: false)
        try store.enqueue(workout, phase: .awaitingHealthKitFinish)
        try store.enqueue(
            progressiveOverload: intent(
                slotID: slotID, sourceWorkoutID: workout.id, sourceRoutineExerciseID: slotID
            ),
            routineID: routineID, transactionID: overloadID
        )

        #expect(store.transportEligibleEntries().map(\.id) == [overloadID])
    }

    @Test
    func repeatedRecapTapsReuseOneTransactionAndOneSequence() throws {
        let directory = try Fixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatchSyncStateStore(directory: directory)
        let routineID = UUID(), transactionID = UUID(), workoutID = UUID(), slotID = UUID()
        let overload = intent(
            slotID: slotID, sourceWorkoutID: workoutID, sourceRoutineExerciseID: slotID
        )

        try store.enqueue(
            progressiveOverload: overload, routineID: routineID, transactionID: transactionID
        )
        try store.enqueue(
            progressiveOverload: overload, routineID: routineID, transactionID: transactionID
        )

        #expect(store.all.count == 1)
        #expect(store.hasPendingTransaction(id: transactionID))
    }

    @Test
    func pendingLookupIsFalseForAnUnknownOrRetiredTransaction() throws {
        let directory = try Fixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatchSyncStateStore(directory: directory)
        let transactionID = UUID()

        #expect(!store.hasPendingTransaction(id: transactionID))
        try store.enqueue(
            progressiveOverload: intent(), routineID: UUID(), transactionID: transactionID
        )
        #expect(store.hasPendingTransaction(id: transactionID))
        store.retire(id: transactionID)
        #expect(!store.hasPendingTransaction(id: transactionID))
    }

    /// Two qualifying exercises get two independent transactions — one row's
    /// apply can never consume or overwrite another's.
    @Test
    func twoRecapExercisesApplyIndependently() throws {
        let directory = try Fixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatchSyncStateStore(directory: directory)
        let routineID = UUID(), workoutID = UUID()
        let first = UUID(), second = UUID()
        let slotA = UUID(), slotB = UUID()

        try store.enqueue(
            progressiveOverload: intent(
                slotID: slotA, sourceWorkoutID: workoutID, sourceRoutineExerciseID: slotA
            ),
            routineID: routineID, transactionID: first
        )
        try store.enqueue(
            progressiveOverload: intent(
                slotID: slotB, sourceWorkoutID: workoutID, sourceRoutineExerciseID: slotB
            ),
            routineID: routineID, transactionID: second
        )

        #expect(store.all.count == 2)
        let sequences = store.all.compactMap { $0.templateTransaction?.sequence }.sorted()
        #expect(sequences == [0, 1])
        #expect(store.hasPendingTransaction(id: first))
        #expect(store.hasPendingTransaction(id: second))
    }
}
