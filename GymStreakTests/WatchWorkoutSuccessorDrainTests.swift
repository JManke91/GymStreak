import Foundation
import Testing
@testable import GymStreak

@MainActor
private final class SuccessorDrainRecordingTransport: WatchWorkoutTransporting {
    var isWorkoutTransportActivated = true
    var isWorkoutMessageReachable = false
    var outstandingWorkoutSemanticIDs: Set<UUID> = []
    private(set) var transfers: [[String: Any]] = []

    func sendWorkoutMessage(_ payload: [String: Any]) {}

    func enqueueWorkoutUserInfo(_ payload: [String: Any]) {
        transfers.append(payload)
        let idString = (payload[WatchWorkoutWire.transactionIdKey] as? String)
            ?? (payload[WatchWorkoutWire.workoutIdKey] as? String)
        if let idString, let id = UUID(uuidString: idString) {
            outstandingWorkoutSemanticIDs.insert(id)
        }
    }

    /// Since the history/template split a template-carrying workout produces
    /// two transfers, so the successor-release assertions count the gated half.
    var templateTransfers: [[String: Any]] {
        transfers.filter { $0[WatchWorkoutWire.templateTransactionKey] != nil }
    }

    var historyWorkoutIDs: Set<UUID> {
        Set(transfers.compactMap {
            ($0[WatchWorkoutWire.workoutIdKey] as? String).flatMap(UUID.init(uuidString:))
        })
    }
}

@Suite(.serialized)
@MainActor
struct WatchWorkoutSuccessorDrainTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures

    @Test
    func acknowledgmentThenContextTransportsAllThreeSuccessorsWithoutForegrounding() throws {
        let routine = Fixtures.makeWatchRoutine()
        let epoch = UUID()
        let store = WatchSyncStateStore(
            directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil
        )
        #expect(bootstrap(store, routine: routine, epoch: epoch))

        let workouts = (0..<3).map { _ in
            Fixtures.makeWorkout(routineId: routine.id, shouldUpdateTemplate: true)
        }
        for workout in workouts {
            try store.enqueue(workout, phase: .transportEligible, routineAnchor: routine)
        }
        let entries = try workouts.map {
            try #require(Fixtures.templateEntry(in: store, forWorkout: $0.id))
        }
        let transport = SuccessorDrainRecordingTransport()
        let coordinator = WatchWorkoutTransportCoordinator(
            syncState: store, transport: transport
        )

        coordinator.reconcile()
        // All three histories go immediately; only the head transaction does.
        #expect(transport.historyWorkoutIDs == Set(workouts.map(\.id)))
        #expect(transport.templateTransfers.count == 1)

        store.acknowledgeTemplateTransaction(ack(for: entries[0], epoch: epoch, generation: 2))
        #expect(transport.templateTransfers.count == 1)
        #expect(store.applyRoutineContext(
            [routine],
            header: RoutineSnapshotHeader(
                epoch: epoch,
                generation: 2,
                targetWatchInstanceID: nil,
                fromEpoch: nil,
                handoverNonce: nil
            )
        ))
        #expect(transport.templateTransfers.count == 2)

        store.acknowledgeTemplateTransaction(ack(for: entries[1], epoch: epoch, generation: 3))
        #expect(store.applyRoutineContext(
            [routine],
            header: RoutineSnapshotHeader(
                epoch: epoch,
                generation: 3,
                targetWatchInstanceID: nil,
                fromEpoch: nil,
                handoverNonce: nil
            )
        ))
        #expect(transport.templateTransfers.count == 3)
    }

    @Test
    func contextThenAcknowledgmentTransportsSuccessorWithoutForegrounding() throws {
        let routine = Fixtures.makeWatchRoutine()
        let epoch = UUID()
        let store = WatchSyncStateStore(
            directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil
        )
        #expect(bootstrap(store, routine: routine, epoch: epoch))

        let firstWorkout = Fixtures.makeWorkout(routineId: routine.id, shouldUpdateTemplate: true)
        try store.enqueue(firstWorkout, phase: .transportEligible, routineAnchor: routine)
        try store.enqueue(
            Fixtures.makeWorkout(routineId: routine.id, shouldUpdateTemplate: true),
            phase: .transportEligible,
            routineAnchor: routine
        )
        let first = try #require(Fixtures.templateEntry(in: store, forWorkout: firstWorkout.id))
        let transport = SuccessorDrainRecordingTransport()
        let coordinator = WatchWorkoutTransportCoordinator(
            syncState: store, transport: transport
        )

        coordinator.reconcile()
        #expect(transport.templateTransfers.count == 1)

        #expect(store.applyRoutineContext(
            [routine],
            header: RoutineSnapshotHeader(
                epoch: epoch,
                generation: 2,
                targetWatchInstanceID: nil,
                fromEpoch: nil,
                handoverNonce: nil
            )
        ))
        #expect(transport.templateTransfers.count == 1)
        store.acknowledgeTemplateTransaction(ack(for: first, epoch: epoch, generation: 2))

        #expect(transport.templateTransfers.count == 2)
    }

    private func bootstrap(
        _ store: WatchSyncStateStore,
        routine: WatchRoutine,
        epoch: UUID
    ) -> Bool {
        let challenge = store.routineChallengeContext
        return store.applyRoutineContext(
            [routine],
            header: RoutineSnapshotHeader(
                epoch: epoch,
                generation: 1,
                targetWatchInstanceID: UUID(
                    uuidString: challenge[WatchRoutineSync.challengeWatchInstanceIDKey]!
                ),
                fromEpoch: store.acceptedRoutineEpoch,
                handoverNonce: UUID(
                    uuidString: challenge[WatchRoutineSync.challengeNonceKey]!
                )
            )
        )
    }

    private func ack(
        for entry: OutgoingSyncEntry,
        epoch: UUID,
        generation: UInt64
    ) -> TemplateAckRecord {
        TemplateAckRecord(
            transactionID: entry.templateTransaction!.transactionID,
            outcomeRaw: "applied",
            senderEpoch: entry.templateTransaction!.senderEpoch,
            sequence: entry.templateTransaction!.sequence,
            routineEpoch: epoch,
            routineGeneration: generation
        )
    }
}
