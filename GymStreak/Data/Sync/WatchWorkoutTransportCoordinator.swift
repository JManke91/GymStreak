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
/// system queue. IDENTICAL COPY in both targets — `GymStreak/Data/Sync/` and
/// `GymStreakWatch Watch App/Managers/` — keep them in sync. The watch target
/// runs it; the iOS copy exists so the policy can be unit-tested (there is no
/// watch unit-test target).
@MainActor
final class WatchWorkoutTransportCoordinator {
    private let syncState: WatchSyncStateStore
    private weak var transport: WatchWorkoutTransporting?
    private var isReconciling = false
    private var needsAnotherReconcile = false

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

    /// Reentrant calls coalesce into one follow-up pass (same contract as the
    /// iOS ingestion drain). `quarantine` below fires the sync state's
    /// eligibility callback — quarantining releases a per-routine FIFO head —
    /// which re-enters here; without coalescing the outer loop would continue
    /// over a stale entry snapshot and a stale `outstandingIDs` set and could
    /// enqueue the released successor twice.
    func reconcile() {
        guard !isReconciling else {
            needsAnotherReconcile = true
            return
        }
        isReconciling = true
        defer {
            isReconciling = false
            if needsAnotherReconcile {
                needsAnotherReconcile = false
                reconcile()
            }
        }

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
                WatchSyncDiagnostics.notice("transport: entry \(WatchSyncDiagnostics.shortID(entry.id)) already outstanding — not re-enqueueing")
                continue
            }
            transport.enqueueWorkoutUserInfo(payload)
            WatchSyncDiagnostics.info("transport: queued entry \(WatchSyncDiagnostics.shortID(entry.id))")
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
