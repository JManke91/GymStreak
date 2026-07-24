import Foundation
import Combine
import WatchConnectivity

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published var isReachable = false

    private var session: WCSession?
    nonisolated private let delegateWorkTracker = WatchConnectivityDelegateWorkTracker()
    private lazy var workoutTransport = WatchWorkoutTransportCoordinator(
        syncState: syncState,
        transport: self
    )
    /// Retained after firing so transient didFinish failures can schedule at
    /// most one delayed retry per process; lifecycle and receiver triggers
    /// remain available afterward without creating a timer loop.
    private var workoutTransportRetryTask: Task<Void, Never>?

    /// The single watch sync-state owner (tickets 04/05): the durable outgoing
    /// workout/template-transaction FIFO, the template sender epoch and
    /// per-routine sequences, the routine authority, and the authoritative
    /// routine base with its optimistic anchors. Frozen payloads enter it
    /// BEFORE HealthKit finalization (via WatchWorkoutFinalizer) and are
    /// retired only by an app-level acknowledgment from iOS. Owned here — the
    /// single WatchConnectivity lifecycle owner — and created eagerly in init,
    /// which AppState.init reaches before any view task runs.
    let syncState = WatchSyncStateStore()

    /// The single owner of the synced exercise catalogue and its inbox. Owned
    /// here (not by AppState) so a cold background wake — where no UI scene and
    /// possibly no AppState exists — still has exactly one store instance to
    /// drain into. AppState exposes it to the view environment.
    private(set) lazy var exerciseCatalogStore: ExerciseCatalogStore = {
        let store = ExerciseCatalogStore()
        store.onChallengeStateChanged = { [weak self] in
            self?.publishChallengeContext()
        }
        return store
    }()

    private override init() {
        super.init()
        // Interrupted-finalization handling moved to ticket 08 recovery: the
        // foreground `WatchWorkoutRecoveryCoordinator` first tries to reconnect
        // the still-active HKWorkoutSession and finish it properly (a blind
        // promotion here would leave a running session that blocks the next
        // workout). Entries it can't reconnect — and a cold background wake with
        // no UI — fall back to `promoteInterruptedFinalizations()`
        // (`handleWatchConnectivityBackgroundWake`), so the durable payload
        // still reaches iOS.
        syncState.onChallengeStateChanged = { [weak self] in
            self?.publishChallengeContext()
        }
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    // MARK: - Exercise catalogue

    /// Publishes the watch → iOS challenge context: the catalogue receiver
    /// challenge (ticket 03) MERGED with the routine authority challenge
    /// (ticket 05). updateApplicationContext replaces this direction's whole
    /// dictionary, so both challenges must always be sent together — sending
    /// either alone would erase the other. Requires activation only;
    /// reachability is irrelevant.
    private func publishChallengeContext() {
        guard let session, session.activationState == .activated else { return }
        var context = syncState.routineChallengeContext
        for (key, value) in exerciseCatalogStore.publishableChallengeContext ?? [:] {
            context[key] = value
        }
        do {
            try session.updateApplicationContext(context)
        } catch {
            print("WatchConnectivity: failed to publish challenge context — \(error.localizedDescription)")
        }
    }

    /// SwiftUI `.backgroundTask(.watchConnectivity)` entry point: keeps the
    /// background wake alive until WCSession has activated, its own delivery
    /// queue is empty (`hasContentPending` covers undelivered *system* content
    /// only, not app-created work), and all app-owned work is idle — the
    /// serialized catalogue-inbox drain, challenge republication, tracked
    /// delegate work, and outgoing-workout transport attempts, each of which persists
    /// atomically before returning. SwiftUI completes the background task when
    /// this async closure returns — no explicit completion call is involved.
    /// On cancellation (system expiry) we stop cleanly; every durable input
    /// (inbox files, queue entries) stays replayable for the next launch.
    func handleWatchConnectivityBackgroundWake() async {
        while !Task.isCancelled {
            guard let session else { return }
            guard session.activationState == .activated, !session.hasContentPending else {
                try? await Task.sleep(for: .milliseconds(250))
                continue
            }

            // Delegate callbacks register synchronously before hopping to the
            // main actor. Wait for those mutations to finish, then re-check the
            // system queue in case more content arrived while they were running.
            await delegateWorkTracker.waitUntilIdle()
            guard !Task.isCancelled else { return }
            await Task.yield()
            if !session.hasContentPending, delegateWorkTracker.isIdle { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard !Task.isCancelled else { return }
        // Synchronous on the main actor: when these return, all persistence
        // for delivered content is committed (or deliberately deferred to a
        // replayable durable input).
        exerciseCatalogStore.drainInbox()
        publishChallengeContext()
        // Background backstop for interrupted finalizations (ticket 08): a cold
        // wake has no UI and no recovery coordinator, so promote any entry a
        // previous process left mid-HealthKit finalization straight to
        // transport-eligible — the durable payload still reaches iOS. Foreground
        // relaunch instead runs WatchWorkoutRecoveryCoordinator, which reconnects
        // the live session before falling back to this promotion.
        syncState.promoteInterruptedFinalizations()
        transportEligibleWorkouts()
    }

    // MARK: - Transport Completed Workouts to iOS

    /// Attempts transport for every transport-eligible workout in the durable
    /// queue. Enqueueing and HealthKit finalization are WatchWorkoutFinalizer's
    /// job — this method never constructs payloads and never touches
    /// HealthKit; it only moves already-finalized frozen bytes. Safe to call
    /// from any lifecycle trigger (activation, reachability change, relaunch,
    /// foreground, background wake, receiver request) and after a coalesced
    /// delayed retry for transient transfer failure.
    ///
    /// The eligible set already applies the per-routine ordering gate (ticket
    /// 05): only the oldest pending template transaction for a routine may be
    /// sent, over either path. The gate is not the ordering authority — a
    /// delayed background duplicate can still overtake — so the receiver's
    /// sequence enforcement and durable receipts are what make a late
    /// duplicate acknowledgment-only.
    func transportEligibleWorkouts() {
        workoutTransport.reconcile()
    }

    private func scheduleWorkoutTransportRetry() {
        guard workoutTransportRetryTask == nil else { return }
        workoutTransportRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            self.transportEligibleWorkouts()
        }
    }

    /// WCError codes that make the current payload bytes permanently
    /// untransportable on this build. Apple defines the codes but no retry
    /// policy — treating them as terminal-for-bytes is deliberate app policy
    /// (mirrors the exercise-catalogue sender's classification).
    nonisolated static func isTerminalTransportError(_ error: Error) -> Bool {
        guard let wcError = error as? WCError else { return false }
        switch wcError.code {
        case .payloadTooLarge, .payloadUnsupportedTypes, .invalidParameter:
            return true
        default:
            return false
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        delegateWorkTracker.beginWork()
        Task { @MainActor in
            defer { self.delegateWorkTracker.endWork() }
            if let error = error {
                print("WatchConnectivity: Activation failed - \(error.localizedDescription)")
                return
            }
            guard activationState == .activated else {
                print("WatchConnectivity: Activation completed in non-active state \(activationState.rawValue)")
                return
            }

            self.isReachable = session.isReachable
            print("WatchConnectivity: Activated on Watch")

            // Bootstrap exactly once after activation. The delegate handles
            // new arrivals; this read recovers the latest context that a
            // previous process already received.
            let applicationContext = session.receivedApplicationContext
            if !applicationContext.isEmpty {
                self.processApplicationContext(applicationContext)
            }

            // Retry transport for any finalized workouts still awaiting an
            // iOS save-ack (bounded lifecycle trigger, not a timer).
            self.transportEligibleWorkouts()

            // Republish the catalogue challenge until consumed (it must
            // survive iOS reinstalls that lost the context) and drain any
            // catalogue files that arrived while no session was active.
            self.publishChallengeContext()
            self.exerciseCatalogStore.drainInbox()
        }
    }

    /// Catalogue snapshots arrive as tagged file transfers. The temporary file
    /// only lives until this callback returns, so it is moved into the owned
    /// App Group inbox synchronously here — never captured across an actor
    /// hop. Workout acks and routine context keep their existing routes; a
    /// catalogue file never enters routine parsing.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?[WatchExerciseCatalogSync.metadataTypeKey] as? String
            == WatchExerciseCatalogSync.metadataTypeValue else {
            print("WatchConnectivity: ignoring file transfer without catalogue tag")
            return
        }
        delegateWorkTracker.beginWork()
        guard ExerciseCatalogInbox.storeIncomingFile(from: file.fileURL) else {
            delegateWorkTracker.endWork()
            return
        }
        Task { @MainActor in
            defer { self.delegateWorkTracker.endWork() }
            self.exerciseCatalogStore.drainInbox()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        delegateWorkTracker.beginWork()
        Task { @MainActor in
            defer { self.delegateWorkTracker.endWork() }
            self.isReachable = session.isReachable
            print("WatchConnectivity: Reachability changed - \(session.isReachable)")

            // Reconcile on every connectivity transition. The durable path
            // does not require reachability; reachability only enables the
            // immediate sendMessage fast path.
            self.transportEligibleWorkouts()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        delegateWorkTracker.beginWork()
        Task { @MainActor in
            defer { self.delegateWorkTracker.endWork() }
            self.processApplicationContext(applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        delegateWorkTracker.beginWork()
        Task { @MainActor in
            defer { self.delegateWorkTracker.endWork() }
            self.handleIncoming(message)
        }
    }

    /// iOS sends the save-acknowledgment via transferUserInfo (guaranteed delivery)
    /// in addition to the sendMessage fast-path, so acks can arrive here too.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        delegateWorkTracker.beginWork()
        Task { @MainActor in
            defer { self.delegateWorkTracker.endWork() }
            self.handleIncoming(userInfo)
        }
    }

    /// Called when a transferUserInfo we initiated finishes — successfully or
    /// with an error. Transport diagnostics ONLY: success is never a removal
    /// signal, because WatchConnectivity reporting that this transfer finished
    /// is not proof that GymStreak on iOS durably persisted it. Removing on this
    /// callback is exactly what historically allowed workouts to be saved to
    /// HealthKit yet never reach iOS history — retirement happens only on the
    /// app-level workoutAck (see `handleIncoming`). Errors are classified:
    /// permanent-for-bytes codes quarantine the entry (no hot-looping a doomed
    /// payload); everything else stays queued and schedules a bounded retry.
    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        let semanticIdString = userInfoTransfer.userInfo[WatchWorkoutWire.transactionIdKey] as? String
            ?? userInfoTransfer.userInfo[WatchWorkoutWire.workoutIdKey] as? String
        delegateWorkTracker.beginWork()
        Task { @MainActor in
            defer { self.delegateWorkTracker.endWork() }
            guard let error = error else {
                print("WatchConnectivity: transferUserInfo delivered to system — awaiting iPhone save ack before clearing")
                return
            }
            if let semanticIdString, let semanticID = UUID(uuidString: semanticIdString),
               Self.isTerminalTransportError(error) {
                self.syncState.quarantine(id: semanticID, reason: "transfer failed permanently: \(error.localizedDescription)")
                return
            }
            print("WatchConnectivity: transferUserInfo failed (scheduling bounded retry) — \(error.localizedDescription)")
            self.scheduleWorkoutTransportRetry()
        }
    }

    /// Routes an incoming payload. Only an app-level acknowledgment — iOS
    /// confirming the workout is durably persisted — can retire a workout;
    /// anything else is treated as a routine sync.
    ///
    /// A versioned acknowledgment (ticket 05) additionally carries the
    /// transaction outcome and the authoritative routine generation it staged:
    /// the sync-state owner holds it until that generation has applied
    /// locally. A plain legacy acknowledgment clears only no-template
    /// workouts — an old iOS build never processed the template intent, so
    /// discarding a template transaction on it would silently drop the user's
    /// requested update.
    @MainActor
    private func handleIncoming(_ payload: [String: Any]) {
        if workoutTransport.handleIncoming(payload) {
            print("WatchConnectivity: received workout queue-drain request from iPhone")
            return
        }
        if let record = TemplateAckRecord.from(payload: payload) {
            syncState.acknowledgeTemplateTransaction(record)
            print("WatchConnectivity: transaction \(record.transactionID) acknowledged (\(record.outcomeRaw)) at routine generation \(record.routineGeneration)")
            return
        }
        if let ackString = payload[WatchWorkoutWire.ackKey] as? String, let id = UUID(uuidString: ackString) {
            syncState.acknowledgePlain(workoutId: id)
            print("WatchConnectivity: workout \(id) acknowledged saved by iPhone (plain ack)")
            return
        }
        processApplicationContext(payload)
    }

    /// Applies an iOS → watch routine snapshot through the routine authority
    /// (ticket 05). An unknown epoch is accepted only as a receiver-authorized
    /// handover; a stale or retired authority can never replace the base. A
    /// legacy unversioned context (pre-ticket-05 iOS) still updates the base
    /// but never establishes or advances a generation. Pending optimistic
    /// template values survive either way — the sync-state owner folds
    /// unresolved transactions over whatever base is newest.
    private func processApplicationContext(_ context: [String: Any]) {
        guard let routineData = context[WatchRoutineSync.contextRoutinesKey] as? Data else {
            return
        }

        do {
            let routines = try JSONDecoder().decode([WatchRoutine].self, from: routineData)
            switch RoutineSnapshotHeader.parse(context: context) {
            case .legacy:
                if syncState.applyRoutineContext(routines, header: nil) {
                    print("WatchConnectivity: Applied \(routines.count) legacy routines from iPhone")
                }
            case .versioned(let header):
                if syncState.applyRoutineContext(routines, header: header) {
                    print("WatchConnectivity: Applied \(routines.count) routines from iPhone (generation \(header.generation))")
                }
            case .malformed:
                print("WatchConnectivity: Rejected malformed versioned routine context")
            }
        } catch {
            print("WatchConnectivity: Failed to decode routines - \(error.localizedDescription)")
        }
    }
}

// MARK: - WatchWorkoutTransporting

extension WatchConnectivityManager: WatchWorkoutTransporting {
    var isWorkoutTransportActivated: Bool {
        session?.activationState == .activated
    }

    var isWorkoutMessageReachable: Bool {
        session?.isReachable == true
    }

    var outstandingWorkoutSemanticIDs: Set<UUID> {
        guard let session else { return [] }
        return Set(session.outstandingUserInfoTransfers.compactMap { transfer in
            let value = (transfer.userInfo[WatchWorkoutWire.transactionIdKey] as? String)
                ?? (transfer.userInfo[WatchWorkoutWire.workoutIdKey] as? String)
            return value.flatMap(UUID.init(uuidString:))
        })
    }

    func sendWorkoutMessage(_ payload: [String: Any]) {
        session?.sendMessage(payload, replyHandler: nil) { error in
            print("WatchConnectivity: sendMessage fast-path failed — \(error.localizedDescription) (transferUserInfo will still deliver)")
        }
    }

    func enqueueWorkoutUserInfo(_ payload: [String: Any]) {
        session?.transferUserInfo(payload)
    }
}
