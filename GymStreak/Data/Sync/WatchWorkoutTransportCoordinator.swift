import Foundation

/// Small WatchConnectivity boundary used by the watch-side workout transport
/// coordinator. The production adapter is `WatchConnectivityManager`; tests
/// use an in-memory transport because WCSession cannot be constructed.
@MainActor
protocol WatchWorkoutTransporting: AnyObject {
    var isWorkoutTransportActivated: Bool { get }
    var isWorkoutMessageReachable: Bool { get }
    var outstandingWorkoutSemanticIDs: Set<UUID> { get }

    func sendWorkoutMessage(_ payload: [String: Any])
    func enqueueWorkoutUserInfo(_ payload: [String: Any])
}

/// Reconciles GymStreak's durable outgoing workout queue with WatchConnectivity's
/// system queue. This file has an identical watch-target copy; the iOS copy
/// exists so the policy can be unit-tested without a watch unit-test target.
@MainActor
final class WatchWorkoutTransportCoordinator {
    private let syncState: WatchSyncStateStore
    private weak var transport: WatchWorkoutTransporting?

    init(syncState: WatchSyncStateStore, transport: WatchWorkoutTransporting) {
        self.syncState = syncState
        self.transport = transport
        syncState.onTransportEligibilityChanged = { [weak self] in
            self?.reconcile()
        }
    }

    @discardableResult
    func handleIncoming(_ payload: [String: Any]) -> Bool {
        guard WatchWorkoutWire.isQueueDrainRequest(payload) else { return false }
        reconcile()
        return true
    }

    func reconcile() {
        guard let transport, transport.isWorkoutTransportActivated else { return }
        let outstandingIDs = transport.outstandingWorkoutSemanticIDs

        for entry in syncState.transportEligibleEntries() {
            let payload: [String: Any]
            do {
                payload = try Self.makePayload(for: entry)
            } catch {
                syncState.quarantine(id: entry.id, reason: "encode failed: \(error.localizedDescription)")
                continue
            }
            guard !payload.isEmpty else {
                syncState.quarantine(id: entry.id, reason: "missing transport payload")
                continue
            }

            if transport.isWorkoutMessageReachable {
                transport.sendWorkoutMessage(payload)
            }
            guard !outstandingIDs.contains(entry.id) else {
                print("WatchConnectivity: sync entry \(entry.id) already outstanding — not re-enqueueing")
                continue
            }
            transport.enqueueWorkoutUserInfo(payload)
            print("WatchConnectivity: queued sync entry \(entry.id)")
        }
    }

    private static func makePayload(for entry: OutgoingSyncEntry) throws -> [String: Any] {
        var payload: [String: Any] = [:]
        if let workout = entry.completedWorkout {
            payload[WatchWorkoutWire.payloadKey] = try JSONEncoder().encode(workout)
            payload[WatchWorkoutWire.workoutIdKey] = workout.id.uuidString
        }
        if let transaction = entry.templateTransaction {
            payload[WatchWorkoutWire.templateTransactionKey] = try JSONEncoder().encode(transaction)
            payload[WatchWorkoutWire.transactionIdKey] = transaction.transactionID.uuidString
        }
        return payload
    }
}
