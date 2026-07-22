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

        let entries = try (0..<3).map { _ in
            try store.enqueue(
                Fixtures.makeWorkout(
                    routineId: routine.id,
                    shouldUpdateTemplate: true
                ),
                phase: .transportEligible,
                routineAnchor: routine
            )
        }
        let transport = SuccessorDrainRecordingTransport()
        let coordinator = WatchWorkoutTransportCoordinator(
            syncState: store, transport: transport
        )

        coordinator.reconcile()
        #expect(transport.transfers.count == 1)

        store.acknowledgeTemplateTransaction(ack(for: entries[0], epoch: epoch, generation: 2))
        #expect(transport.transfers.count == 1)
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
        #expect(transport.transfers.count == 2)

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
        #expect(transport.transfers.count == 3)
    }

    @Test
    func contextThenAcknowledgmentTransportsSuccessorWithoutForegrounding() throws {
        let routine = Fixtures.makeWatchRoutine()
        let epoch = UUID()
        let store = WatchSyncStateStore(
            directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil
        )
        #expect(bootstrap(store, routine: routine, epoch: epoch))

        let first = try store.enqueue(
            Fixtures.makeWorkout(routineId: routine.id, shouldUpdateTemplate: true),
            phase: .transportEligible,
            routineAnchor: routine
        )
        _ = try store.enqueue(
            Fixtures.makeWorkout(routineId: routine.id, shouldUpdateTemplate: true),
            phase: .transportEligible,
            routineAnchor: routine
        )
        let transport = SuccessorDrainRecordingTransport()
        let coordinator = WatchWorkoutTransportCoordinator(
            syncState: store, transport: transport
        )

        coordinator.reconcile()
        #expect(transport.transfers.count == 1)

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
        #expect(transport.transfers.count == 1)
        store.acknowledgeTemplateTransaction(ack(for: first, epoch: epoch, generation: 2))

        #expect(transport.transfers.count == 2)
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
