import Foundation
import Testing
@testable import GymStreak

@MainActor
private final class RecordingWorkoutTransport: WatchWorkoutTransporting {
    var isWorkoutTransportActivated = false
    var isWorkoutMessageReachable = false
    var outstandingWorkoutSemanticIDs: Set<UUID> = []
    private(set) var messages: [[String: Any]] = []
    private(set) var transfers: [[String: Any]] = []

    func sendWorkoutMessage(_ payload: [String: Any]) {
        messages.append(payload)
    }

    func enqueueWorkoutUserInfo(_ payload: [String: Any]) {
        transfers.append(payload)
        let id = (payload[WatchWorkoutWire.transactionIdKey] as? String)
            ?? (payload[WatchWorkoutWire.workoutIdKey] as? String)
        if let id, let uuid = UUID(uuidString: id) {
            outstandingWorkoutSemanticIDs.insert(uuid)
        }
    }
}

@Suite(.serialized)
@MainActor
struct WatchWorkoutTransportCoordinatorTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures

    @Test
    func iOSLaunchDrainRequestRequeuesWorkoutAfterOfflineActivation() throws {
        let store = WatchSyncStateStore(
            directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil
        )
        let workout = Fixtures.makeWorkout()
        try store.enqueue(workout, phase: .transportEligible)
        let transport = RecordingWorkoutTransport()
        let coordinator = WatchWorkoutTransportCoordinator(
            syncState: store, transport: transport
        )

        coordinator.reconcile()
        #expect(transport.transfers.isEmpty)

        transport.isWorkoutTransportActivated = true
        let handled = coordinator.handleIncoming(["requestWorkoutQueueDrain": "1"])

        #expect(handled)
        #expect(transport.transfers.count == 1)
        #expect(store.entry(id: workout.id) != nil)
    }

    @Test
    func durableDrainRequestDoesNotDuplicateOutstandingTransfer() throws {
        let store = WatchSyncStateStore(
            directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil
        )
        let workout = Fixtures.makeWorkout()
        try store.enqueue(workout, phase: .transportEligible)
        let transport = RecordingWorkoutTransport()
        transport.isWorkoutTransportActivated = true
        transport.outstandingWorkoutSemanticIDs = [workout.id]
        let coordinator = WatchWorkoutTransportCoordinator(
            syncState: store, transport: transport
        )

        let handled = coordinator.handleIncoming(WatchWorkoutWire.queueDrainRequestPayload)

        #expect(handled)
        #expect(transport.messages.isEmpty)
        #expect(transport.transfers.isEmpty)
        #expect(store.entry(id: workout.id) != nil)
    }

    @Test
    func ordinaryReconcileDoesNotDuplicateAnOutstandingTransfer() throws {
        let store = WatchSyncStateStore(
            directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil
        )
        let workout = Fixtures.makeWorkout()
        try store.enqueue(workout, phase: .transportEligible)
        let transport = RecordingWorkoutTransport()
        transport.isWorkoutTransportActivated = true
        transport.outstandingWorkoutSemanticIDs = [workout.id]
        let coordinator = WatchWorkoutTransportCoordinator(
            syncState: store, transport: transport
        )

        coordinator.reconcile()

        #expect(transport.transfers.isEmpty)
        #expect(store.entry(id: workout.id) != nil)
    }

    @Test
    func missingSystemTransferIsRequeuedUntilAppAcknowledgmentRetiresWorkout() throws {
        let directory = try Fixtures.makeTempDirectory()
        let workout = Fixtures.makeWorkout()
        let store = WatchSyncStateStore(directory: directory, legacyDefaults: nil)
        try store.enqueue(workout, phase: .transportEligible)
        let transport = RecordingWorkoutTransport()
        transport.isWorkoutTransportActivated = true
        let coordinator = WatchWorkoutTransportCoordinator(
            syncState: store, transport: transport
        )

        coordinator.reconcile()
        #expect(transport.transfers.count == 1)
        #expect(store.entry(id: workout.id) != nil)

        // Model WatchConnectivity losing its private queued payload: the
        // semantic ID is no longer outstanding, but no app-level ack arrived.
        transport.outstandingWorkoutSemanticIDs.remove(workout.id)
        let reloadedStore = WatchSyncStateStore(directory: directory, legacyDefaults: nil)
        let relaunchedCoordinator = WatchWorkoutTransportCoordinator(
            syncState: reloadedStore, transport: transport
        )

        relaunchedCoordinator.reconcile()

        #expect(transport.transfers.count == 2)
        #expect(reloadedStore.entry(id: workout.id) != nil)

        reloadedStore.acknowledgePlain(workoutId: workout.id)
        #expect(reloadedStore.entry(id: workout.id) == nil)
    }

    @Test
    func fastDrainRequestUsesMessageWithoutDuplicatingOutstandingTransfer() throws {
        let store = WatchSyncStateStore(
            directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil
        )
        let workout = Fixtures.makeWorkout()
        try store.enqueue(workout, phase: .transportEligible)
        let transport = RecordingWorkoutTransport()
        transport.isWorkoutTransportActivated = true
        transport.isWorkoutMessageReachable = true
        transport.outstandingWorkoutSemanticIDs = [workout.id]
        let coordinator = WatchWorkoutTransportCoordinator(
            syncState: store, transport: transport
        )

        let handled = coordinator.handleIncoming(WatchWorkoutWire.queueDrainRequestPayload)

        #expect(handled)
        #expect(transport.messages.count == 1)
        #expect(transport.transfers.isEmpty)
    }

    @Test
    func unrelatedPayloadIsNotHandledOrTransported() throws {
        let store = WatchSyncStateStore(
            directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil
        )
        let workout = Fixtures.makeWorkout()
        try store.enqueue(workout, phase: .transportEligible)
        let transport = RecordingWorkoutTransport()
        transport.isWorkoutTransportActivated = true
        let coordinator = WatchWorkoutTransportCoordinator(
            syncState: store, transport: transport
        )

        let handled = coordinator.handleIncoming(
            [WatchWorkoutWire.queueDrainRequestKey: "2"]
        )

        #expect(!handled)
        #expect(transport.messages.isEmpty)
        #expect(transport.transfers.isEmpty)
    }
}
