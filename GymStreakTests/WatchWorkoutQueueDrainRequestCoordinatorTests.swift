import Testing
@testable import GymStreak

@MainActor
private final class RecordingQueueDrainRequestTransport:
    WatchWorkoutQueueDrainRequestTransporting {
    var isWorkoutQueueDrainTransportReady = false
    var isWorkoutQueueDrainMessageReachable = false
    var hasOutstandingWorkoutQueueDrainRequest = false
    private(set) var messages: [[String: Any]] = []
    private(set) var transfers: [[String: Any]] = []

    func sendWorkoutQueueDrainMessage(_ payload: [String: Any]) {
        messages.append(payload)
    }

    func enqueueWorkoutQueueDrainUserInfo(_ payload: [String: Any]) {
        transfers.append(payload)
        hasOutstandingWorkoutQueueDrainRequest = true
    }
}

@Suite
@MainActor
struct WatchWorkoutQueueDrainRequestCoordinatorTests {
    @Test
    func inactiveSessionDoesNothing() {
        let transport = RecordingQueueDrainRequestTransport()
        let coordinator = WatchWorkoutQueueDrainRequestCoordinator(transport: transport)

        coordinator.requestDrain()

        #expect(transport.messages.isEmpty)
        #expect(transport.transfers.isEmpty)
    }

    @Test
    func unreachableWatchReceivesOneDurableRequest() {
        let transport = RecordingQueueDrainRequestTransport()
        transport.isWorkoutQueueDrainTransportReady = true
        let coordinator = WatchWorkoutQueueDrainRequestCoordinator(transport: transport)

        coordinator.requestDrain()

        #expect(transport.messages.isEmpty)
        #expect(transport.transfers.count == 1)
        #expect(WatchWorkoutWire.isQueueDrainRequest(transport.transfers[0]))
    }

    @Test
    func reachableWatchUsesFastPathWithoutDuplicatingOutstandingRequest() {
        let transport = RecordingQueueDrainRequestTransport()
        transport.isWorkoutQueueDrainTransportReady = true
        transport.isWorkoutQueueDrainMessageReachable = true
        transport.hasOutstandingWorkoutQueueDrainRequest = true
        let coordinator = WatchWorkoutQueueDrainRequestCoordinator(transport: transport)

        coordinator.requestDrain()

        #expect(transport.messages.count == 1)
        #expect(WatchWorkoutWire.isQueueDrainRequest(transport.messages[0]))
        #expect(transport.transfers.isEmpty)
    }

    @Test
    func postRebootReachableActivationDoesNotAddBackgroundRequest() {
        let transport = RecordingQueueDrainRequestTransport()
        transport.isWorkoutQueueDrainTransportReady = true
        transport.isWorkoutQueueDrainMessageReachable = true
        let coordinator = WatchWorkoutQueueDrainRequestCoordinator(transport: transport)

        coordinator.requestDrain()

        #expect(transport.messages.count == 1)
        #expect(transport.transfers.isEmpty)
    }

    @Test
    func failedReachableMessageFallsBackToOneDurableRequest() {
        let transport = RecordingQueueDrainRequestTransport()
        transport.isWorkoutQueueDrainTransportReady = true
        transport.isWorkoutQueueDrainMessageReachable = true
        let coordinator = WatchWorkoutQueueDrainRequestCoordinator(transport: transport)

        coordinator.requestDrain()
        coordinator.messageSendFailed()
        coordinator.messageSendFailed()

        #expect(transport.messages.count == 1)
        #expect(transport.transfers.count == 1)
        #expect(WatchWorkoutWire.isQueueDrainRequest(transport.transfers[0]))
    }

    @Test
    func failedReachableMessageDoesNotDuplicateOutstandingDurableRequest() {
        let transport = RecordingQueueDrainRequestTransport()
        transport.isWorkoutQueueDrainTransportReady = true
        transport.isWorkoutQueueDrainMessageReachable = true
        transport.hasOutstandingWorkoutQueueDrainRequest = true
        let coordinator = WatchWorkoutQueueDrainRequestCoordinator(transport: transport)

        coordinator.requestDrain()
        coordinator.messageSendFailed()

        #expect(transport.messages.count == 1)
        #expect(transport.transfers.isEmpty)
    }
}
