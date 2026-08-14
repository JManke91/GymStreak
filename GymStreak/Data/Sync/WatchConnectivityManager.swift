import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject, WatchSyncServicing,
    WatchRoutineSnapshotTransporting {
    static let shared = WatchConnectivityManager()

    @Published var isReachable = false
    @Published var isPaired = false
    @Published var isWatchAppInstalled = false

    private var session: WCSession?

    /// Durable receive inbox for completed watch workouts (ticket 04). Owned
    /// here because payload bytes must be persisted synchronously inside the
    /// receive callbacks — BEFORE any ingestion, notification, or ack. Drained
    /// serially by WatchWorkoutIngestionCoordinator (composition root).
    let workoutInbox = WatchWorkoutInboxStore()

    /// Set by the composition root's ingestion coordinator. Invoked after a
    /// payload was durably persisted to the inbox and on session activation,
    /// so the coordinator drains on receipt, launch, and activation.
    var onWorkoutInboxUpdated: (() -> Void)?
    var onRoutineChallengeUpdated: (() -> Void)?

    /// State machine for the exercise-catalogue file sync. Lazy so `self` can
    /// be its transport; this manager is an app-lifetime singleton.
    private lazy var catalogSender = ExerciseCatalogSender(transport: self)

    /// iOS-side policy for the receiver-driven workout replay request.
    private lazy var workoutQueueDrainRequester = WatchWorkoutQueueDrainRequestCoordinator(
        transport: self
    )

    /// The single serialized owner of routine context generations (ticket 05).
    /// Ordinary list syncs and authoritative post-commit snapshots both go
    /// through it, so no two paths can emit competing versions.
    private lazy var routineAuthority = RoutineSyncAuthority(transport: self)

    private override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    // MARK: - Pending Workout Handling

    /// Returns all workouts currently in the durable inbox but not yet
    /// committed to SwiftData. Read-only view for the HealthKit reconciler
    /// (orphan detection); removal is the ingestion coordinator's job.
    func pendingWorkouts() -> [IncomingWatchWorkout] {
        workoutInbox.entries().compactMap { $0.completedWorkout?.toIncomingWatchWorkout() }
    }

    /// Sends an app-level acknowledgment to the watch confirming a completed workout
    /// has been committed to SwiftData (or recognized as already present). The watch
    /// keeps the workout in its durable retry queue until it receives this ack —
    /// WatchConnectivity's own transfer-completion callback only confirms transport
    /// delivery, not that iOS persisted the workout, so without this ack a workout can
    /// be silently lost (present in HealthKit but never in iOS history). Sent over both
    /// the sendMessage fast-path (when reachable) and transferUserInfo (guaranteed),
    /// and re-sent whenever a duplicate arrives, so delivery is self-healing.
    func acknowledgeWorkoutSaved(id: UUID) {
        sendAck(
            [WatchWorkoutWire.ackKey: id.uuidString],
            description: "save-ack for workout \(WatchSyncDiagnostics.shortID(id))"
        )
    }

    /// Sends the versioned terminal acknowledgment for a template transaction
    /// (ticket 05). It carries the workout id under the legacy `workoutAck`
    /// key as well, so an older watch build still reads it as a plain
    /// acknowledgment and ignores the extra fields. All values are
    /// property-list-safe strings.
    func acknowledgeTemplateTransaction(_ ack: WatchTemplateTransactionAck) {
        var payload: [String: Any] = [
            WatchRoutineSync.ackVersionKey: String(WatchRoutineSync.templateUpdateVersion),
            WatchRoutineSync.ackTransactionIDKey: ack.transactionID.uuidString,
            WatchRoutineSync.ackOutcomeKey: ack.outcome.rawValue,
            WatchRoutineSync.ackSenderEpochKey: ack.senderEpoch.uuidString,
            WatchRoutineSync.ackSequenceKey: String(ack.sequence),
            WatchRoutineSync.ackRoutineEpochKey: ack.routineEpoch.uuidString,
            WatchRoutineSync.ackRoutineGenerationKey: String(ack.routineGeneration)
        ]
        if let workoutId = ack.workoutId {
            payload[WatchWorkoutWire.ackKey] = workoutId.uuidString
        }
        sendAck(
            payload,
            description: "\(ack.outcome.rawValue) template ack for transaction "
                + "\(WatchSyncDiagnostics.shortID(ack.transactionID)) at routine generation \(ack.routineGeneration)"
        )
    }

    private func sendAck(_ payload: [String: Any], description: String) {
        guard let session = session, session.activationState == .activated else {
            return
        }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                WatchSyncDiagnostics.notice("phone: ack sendMessage failed — \(error.localizedDescription) (transferUserInfo will still deliver)")
            }
        }
        session.transferUserInfo(payload)
        WatchSyncDiagnostics.info("phone: sent \(description)")
    }

    var watchRoutineChallenge: (epoch: UUID?, generation: UInt64)? {
        routineAuthority.publishedChallenge
    }

    /// True while WatchConnectivity may still be holding watch content it has
    /// received but not yet delivered to our delegate (or the session hasn't
    /// finished activating). `hasContentPending` is only meaningful after
    /// activation and is a *positive* signal only: it cannot see payloads the
    /// watch has queued but that haven't crossed the radio yet — callers must
    /// combine it with a grace period (see `WorkoutViewModel.reconcileWatchWorkouts`).
    var mayHaveUndeliveredContent: Bool {
        guard let session, session.activationState == .activated else {
            return true
        }
        return session.hasContentPending
    }

    // MARK: - Public Methods

    /// Requests that the watch reconcile GymStreak's durable workout queue
    /// with WatchConnectivity's system queue. `transferUserInfo` makes the
    /// request survive an unreachable watch; `sendMessage` is only a fast path.
    /// At most one durable request is outstanding, so repeated foreground
    /// events cannot grow the system queue.
    func requestWorkoutQueueDrain() {
        workoutQueueDrainRequester.requestDrain()
    }

    /// Ordinary routine list sync. Versioned and suppressed-if-identical by
    /// the routine authority; the watch applies it only if it is newer than
    /// what it already accepted, so a delayed context can never regress it.
    func syncRoutines(_ routines: [Routine]) {
        syncRoutineSnapshot(routines.map { $0.toWatchRoutine() })
    }

    func syncRoutineSnapshot(_ routines: [WatchRoutine]) {
        guard canSyncRoutines else { return }
        routineAuthority.sendOrdinary(routines)
    }

    /// Stages the authoritative post-commit routine list for a template
    /// transaction and returns the version the watch will apply. Never
    /// suppressed as a duplicate: a deliberately rejected transaction leaves
    /// the routine bytes unchanged but its acknowledgment still has to name a
    /// correlated generation.
    @discardableResult
    func stageAuthoritativeRoutineSnapshot(
        _ routines: [WatchRoutine]
    ) -> (epoch: UUID, generation: UInt64)? {
        guard canSyncRoutines else { return nil }
        return routineAuthority.sendAuthoritative(routines)
    }

    private var canSyncRoutines: Bool {
        guard let session = session, session.activationState == .activated else {
            WatchSyncDiagnostics.notice("phone: cannot sync routines — session not activated")
            return false
        }
        // On simulator, isWatchAppInstalled is always false even when Watch app is running
        #if !targetEnvironment(simulator)
        guard session.isWatchAppInstalled else {
            WatchSyncDiagnostics.notice("phone: cannot sync routines — Watch app not installed")
            return false
        }
        #endif
        return true
    }

    /// Deterministic encoding (sorted keys) so identical routine content always
    /// produces identical bytes — the basis of the duplicate-sync suppression.
    static func encodeRoutinesPayload(_ routines: [WatchRoutine]) -> Data? {
        RoutineSyncAuthority.encode(routines)
    }

    /// Stages the current exercise library as a full catalogue snapshot. The
    /// sender persists it durably and transfers it when the session, watch
    /// state, and receiver challenge allow — callers never need to check
    /// reachability or session state.
    func syncExerciseCatalog(_ exercises: [Exercise]) {
        catalogSender.requestSync(items: WatchExerciseCatalogMapper.items(from: exercises))
    }
}

// MARK: - WatchWorkoutQueueDrainRequestTransporting

extension WatchConnectivityManager: WatchWorkoutQueueDrainRequestTransporting {
    var isWorkoutQueueDrainTransportReady: Bool {
        guard let session else { return false }
        return session.activationState == .activated
            && session.isPaired
            && session.isWatchAppInstalled
    }

    var isWorkoutQueueDrainMessageReachable: Bool {
        session?.isReachable == true
    }

    var hasOutstandingWorkoutQueueDrainRequest: Bool {
        session?.outstandingUserInfoTransfers.contains { transfer in
            WatchWorkoutWire.isQueueDrainRequest(transfer.userInfo)
        } == true
    }

    func sendWorkoutQueueDrainMessage(_ payload: [String: Any]) {
        session?.sendMessage(payload, replyHandler: nil) { [weak self] error in
            WatchSyncDiagnostics.notice("phone: workout queue-drain fast path failed — \(error.localizedDescription)")
            Task { @MainActor in
                self?.workoutQueueDrainRequester.messageSendFailed()
            }
        }
    }

    func enqueueWorkoutQueueDrainUserInfo(_ payload: [String: Any]) {
        session?.transferUserInfo(payload)
        WatchSyncDiagnostics.info("phone: requested workout queue drain from Watch")
    }
}

// MARK: - RoutineContextTransporting

extension WatchConnectivityManager: RoutineContextTransporting {
    func sendRoutineContext(_ context: [String: Any]) throws {
        guard let session else { throw WCError(.sessionNotActivated) }
        try session.updateApplicationContext(context)
    }

    /// Defence in depth for the authority's challenge lookup, NOT the primary
    /// path — `canSyncRoutines` refuses to send before activation anyway, so
    /// the pre-activation window is handled by ordering the challenge update
    /// ahead of the inbox drain in `activationDidCompleteWith`. This covers the
    /// cases where the challenge only ever arrived via `didReceiveApplicationContext`.
    /// Deliberately not gated on `activationState`: it is a plain property read
    /// with no documented activation precondition, and an empty dictionary is
    /// the correct "nothing known yet" answer.
    var receivedWatchContext: [String: Any] {
        session?.receivedApplicationContext ?? [:]
    }
}

// MARK: - ExerciseCatalogTransporting

extension WatchConnectivityManager: ExerciseCatalogTransporting {
    var isReadyForCatalogTransfer: Bool {
        guard let session, session.activationState == .activated else { return false }
        // On simulator, isPaired/isWatchAppInstalled are always false even when
        // the Watch app runs — but transferFile is not exercised by the
        // simulator anyway (paired hardware only).
        #if targetEnvironment(simulator)
        return true
        #else
        return session.isPaired && session.isWatchAppInstalled
        #endif
    }

    func cancelOutstandingCatalogTransfers() {
        guard let session else { return }
        for transfer in session.outstandingFileTransfers where
            transfer.file.metadata?[WatchExerciseCatalogSync.metadataTypeKey] as? String
                == WatchExerciseCatalogSync.metadataTypeValue {
            transfer.cancel()
        }
    }

    func transferCatalogFile(at url: URL, metadata: [String: Any]) {
        session?.transferFile(url, metadata: metadata)
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // `WCSession` is a non-`Sendable` class and must not cross to the main
        // actor. Read the flags here, synchronously, and send only the `Bool`s.
        let isPaired = session.isPaired
        let isWatchAppInstalled = session.isWatchAppInstalled
        let isReachable = session.isReachable
        let errorDescription = error?.localizedDescription
        // The session's *mutable* snapshot state (`receivedApplicationContext`,
        // `outstandingFileTransfers`) is deliberately NOT hoisted here. It is read
        // inside the hop from the stored `self.session`, so it is still sampled on
        // the main actor at the moment it is used. Hoisting it would open a window
        // between this callback and the hop in which a newly started catalogue
        // transfer would be missing from `keeping:` and its staging file deleted
        // as an orphan mid-flight.
        Task { @MainActor in
            if let errorDescription {
                WatchSyncDiagnostics.error("phone: WCSession activation failed — \(errorDescription)")
                return
            }
            guard activationState == .activated else {
                WatchSyncDiagnostics.error("phone: WCSession activation completed in non-active state \(activationState.rawValue)")
                return
            }

            self.isPaired = isPaired
            self.isWatchAppInstalled = isWatchAppInstalled
            self.isReachable = isReachable

            WatchSyncDiagnostics.info("phone: WCSession activated — paired: \(isPaired), installed: \(isWatchAppInstalled)")

            // Catalogue sync lifecycle: recover the watch's challenge (WC
            // re-delivers receivedApplicationContext across launches), drop
            // staging files no outstanding transfer references anymore, and
            // re-enqueue the latest staged snapshot.
            //
            // ORDER IS LOAD-BEARING: this must run BEFORE the inbox drain
            // below. `canSyncRoutines` refuses to send until activation, so
            // the drain in `AppDependencies.init` can never stage an
            // authoritative routine snapshot — this callback is the first
            // moment it becomes possible. Draining first meant a template
            // transaction committed here found no challenge, parked its
            // receipt at `committedAwaitingContext`, never sent its terminal
            // acknowledgment, and permanently pinned the watch's per-routine
            // FIFO head — silently blocking every later workout for that
            // routine from being transmitted at all.
            let receivedContext = self.session?.receivedApplicationContext ?? [:]
            if !receivedContext.isEmpty {
                self.catalogSender.updateChallenge(fromApplicationContext: receivedContext)
                self.routineAuthority.updateChallenge(fromApplicationContext: receivedContext)
                self.onRoutineChallengeUpdated?()
            }

            // Drain the durable inbox (e.g. entries left by a previous launch
            // that crashed before the SwiftData save committed).
            self.onWorkoutInboxUpdated?()
            self.catalogSender.cleanUpOrphanedStagingFiles(
                keeping: self.session?.outstandingFileTransfers.map { $0.file.fileURL } ?? []
            )
            self.catalogSender.sessionDidBecomeReady()

            // iOS cannot pull watch-owned userInfo. Ask the watch to reconcile
            // its durable queue whenever this process activates so a transfer
            // that failed while the phone was powered off self-heals.
            self.requestWorkoutQueueDrain()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        WatchSyncDiagnostics.info("phone: WCSession became inactive")
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WatchSyncDiagnostics.info("phone: WCSession deactivated — reactivating for watch switch")
        // Reactivate session for switching watches
        session.activate()
        Task { @MainActor in
            // A different watch has its own (empty) applicationContext — the
            // duplicate-sync suppression must not starve it.
            self.routineAuthority.resetSuppression()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let isReachable = session.isReachable
        Task { @MainActor in
            self.isReachable = isReachable
            WatchSyncDiagnostics.info("phone: reachability changed — \(isReachable)")
            if isReachable {
                self.requestWorkoutQueueDrain()
            }
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let isPaired = session.isPaired
        let isWatchAppInstalled = session.isWatchAppInstalled
        Task { @MainActor in
            self.isPaired = isPaired
            self.isWatchAppInstalled = isWatchAppInstalled
            WatchSyncDiagnostics.info("phone: watch state changed — paired: \(isPaired), installed: \(isWatchAppInstalled)")

            // Notify so RoutinesViewModel can trigger sync
            if isWatchAppInstalled {
                // A newly installed/switched watch app must receive the
                // current routines even if the content hasn't changed.
                self.routineAuthority.resetSuppression()
                NotificationCenter.default.post(name: .watchAppBecameAvailable, object: nil)
                // Newly paired/installed/switched watch: re-enqueue the latest
                // staged catalogue snapshot (a switched watch will publish its
                // own challenge, which restages a targeted handover).
                self.catalogSender.sessionDidBecomeReady()
                self.requestWorkoutQueueDrain()
            }
        }
    }

    /// Watch → iOS applicationContext carries both receiver challenges — the
    /// catalogue's (ticket 03) and the routine authority's (ticket 05) — in
    /// one merged dictionary. Reachability-independent.
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        // `[String: Any]` is not `Sendable`; box it for the hop (see WatchWirePayload).
        let context = WatchWirePayload(applicationContext)
        Task { @MainActor in
            self.catalogSender.updateChallenge(fromApplicationContext: context.payload)
            self.routineAuthority.updateChallenge(fromApplicationContext: context.payload)
            self.onRoutineChallengeUpdated?()
        }
    }

    /// Completion of a catalogue file transfer — success or error. The sender
    /// owns the staging file's lifetime and the retry/poison classification.
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let metadata = fileTransfer.file.metadata
        guard metadata?[WatchExerciseCatalogSync.metadataTypeKey] as? String
            == WatchExerciseCatalogSync.metadataTypeValue else { return }
        let fileURL = fileTransfer.file.fileURL
        let snapshotID = (metadata?[WatchExerciseCatalogSync.metadataSnapshotIDKey] as? String)
            .flatMap(UUID.init(uuidString:))
        Task { @MainActor in
            self.catalogSender.transferDidFinish(fileURL: fileURL, snapshotID: snapshotID, error: error)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didFinish userInfoTransfer: WCSessionUserInfoTransfer,
        error: Error?
    ) {
        guard WatchWorkoutWire.isQueueDrainRequest(userInfoTransfer.userInfo) else { return }
        if let error {
            WatchSyncDiagnostics.notice("phone: workout queue-drain transfer failed — \(error.localizedDescription)")
        } else {
            WatchSyncDiagnostics.info("phone: workout queue-drain transfer completed")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let boxed = WatchWirePayload(userInfo)
        Task { @MainActor in
            self.handleIncomingPayload(boxed.payload, source: "userInfo")
        }
    }

    /// Watch sends completed workouts via sendMessage as a fast-path when iOS is
    /// reachable, so we must accept them on this delegate too. transferUserInfo
    /// always also fires for the same workout — iOS-side dedupe handles duplicates.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let boxed = WatchWirePayload(message)
        Task { @MainActor in
            self.handleIncomingPayload(boxed.payload, source: "message")
        }
    }

    @MainActor
    private func handleIncomingPayload(_ payload: [String: Any], source: String) {
        if let transactionData = payload[WatchWorkoutWire.templateTransactionKey] as? Data,
           let idString = payload[WatchWorkoutWire.transactionIdKey] as? String,
           let transactionID = UUID(uuidString: idString) {
            do {
                try workoutInbox.store(transactionData: transactionData, transactionID: transactionID)
            } catch {
                WatchSyncDiagnostics.error("inbox: failed to persist template transaction via \(source) — \(error.localizedDescription); not acknowledged, watch will redeliver")
                return
            }
            WatchSyncDiagnostics.info("inbox: received template transaction \(WatchSyncDiagnostics.shortID(transactionID)) via \(source)")
            onWorkoutInboxUpdated?()
            return
        }
        // Validate only the routing envelope here; full decoding happens in
        // the coordinator's serialized drain.
        guard let workoutData = payload[WatchWorkoutWire.payloadKey] as? Data else {
            return
        }
        guard let idString = payload[WatchWorkoutWire.workoutIdKey] as? String,
              let workoutId = UUID(uuidString: idString) else {
            WatchSyncDiagnostics.error("inbox: workout payload without valid id via \(source) — ignored")
            return
        }
        do {
            // Persist the exact bytes BEFORE any ingestion, notification, or
            // ack — WC receive callbacks are not an app-persistence boundary.
            try workoutInbox.store(payloadData: workoutData, workoutId: workoutId)
        } catch {
            // No ack is ever sent for this delivery, so the watch's durable
            // queue keeps the workout replayable.
            WatchSyncDiagnostics.error("inbox: failed to persist incoming workout via \(source) — \(error.localizedDescription); not acknowledged, watch will redeliver")
            return
        }
        WatchSyncDiagnostics.info("inbox: received completed workout \(WatchSyncDiagnostics.shortID(workoutId)) from Watch via \(source)")
        onWorkoutInboxUpdated?()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let watchAppBecameAvailable = Notification.Name("watchAppBecameAvailable")
    /// Posted after a watch-originated WorkoutSession has been committed to
    /// SwiftData. Lets the History tab refresh without a tab switch.
    static let workoutHistoryDidChange = Notification.Name("workoutHistoryDidChange")
    /// Posted after a routine template is mutated outside of RoutinesViewModel
    /// (e.g. editing a past workout in History). Triggers a routine re-fetch +
    /// watch sync so the corrected values reach iOS and the watch.
    static let routineTemplateDidChange = Notification.Name("routineTemplateDidChange")
    /// Posted after a watch template transaction committed. Refreshes cached
    /// routine lists WITHOUT triggering a watch sync: that transaction already
    /// staged its own authoritative snapshot, and an ordinary sync from a
    /// stale cache could emit a competing generation.
    static let routineTemplateDidChangeLocally = Notification.Name("routineTemplateDidChangeLocally")
}
