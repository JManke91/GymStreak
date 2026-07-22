import Foundation

@MainActor
protocol WatchWorkoutQueueDrainRequestTransporting: AnyObject {
    var isWorkoutQueueDrainTransportReady: Bool { get }
    var isWorkoutQueueDrainMessageReachable: Bool { get }
    var hasOutstandingWorkoutQueueDrainRequest: Bool { get }

    func sendWorkoutQueueDrainMessage(_ payload: [String: Any])
    func enqueueWorkoutQueueDrainUserInfo(_ payload: [String: Any])
}

/// iOS-side policy for asking Watch to replay its app-owned workout queue.
/// Lifecycle ownership stays in the app/WCSession adapter; this coordinator
/// makes the dual-path and outstanding-request rules independently testable.
@MainActor
final class WatchWorkoutQueueDrainRequestCoordinator {
    private weak var transport: WatchWorkoutQueueDrainRequestTransporting?

    init(transport: WatchWorkoutQueueDrainRequestTransporting) {
        self.transport = transport
    }

    func requestDrain() {
        guard let transport, transport.isWorkoutQueueDrainTransportReady else { return }
        let payload = WatchWorkoutWire.queueDrainRequestPayload
        if transport.isWorkoutQueueDrainMessageReachable {
            transport.sendWorkoutQueueDrainMessage(payload)
            return
        }
        guard !transport.hasOutstandingWorkoutQueueDrainRequest else { return }
        transport.enqueueWorkoutQueueDrainUserInfo(payload)
    }

    /// Called by the WCSession adapter only when the reachable `sendMessage`
    /// attempt fails. Re-checking readiness and the system queue here keeps the
    /// fallback durable without allowing repeated callbacks to add duplicates.
    func messageSendFailed() {
        guard let transport,
              transport.isWorkoutQueueDrainTransportReady,
              !transport.hasOutstandingWorkoutQueueDrainRequest else { return }
        transport.enqueueWorkoutQueueDrainUserInfo(WatchWorkoutWire.queueDrainRequestPayload)
    }
}
