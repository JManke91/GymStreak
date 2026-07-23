//
//  ExerciseCatalogSender.swift
//  GymStreak
//
//  iOS-side state machine for the exercise-catalogue file sync (ticket 03,
//  in-workout routine editing; see docs/watch-sync.md). Owns the persisted
//  authority-epoch/generation state, stages full-replacement snapshots as
//  JSON files, and hands them to WatchConnectivity via the transport seam.
//
//  Invariants:
//  - State is persisted atomically BEFORE any transfer is enqueued; a failed
//    state write enqueues nothing.
//  - No snapshot is sent until the watch's challenge (applicationContext) has
//    arrived — an unknown receiver epoch requires a receiver-authorized
//    handover targeted at the exact challenge tuple.
//  - Cancelling superseded transfers is queue pruning only; correctness comes
//    from full replacement + the receiver's epoch/generation comparison.
//

import Foundation
import WatchConnectivity

@MainActor
final class ExerciseCatalogSender {
    private let directory: URL
    private let stagingDirectory: URL
    private let stateFileURL: URL
    /// unowned: in production the app-lifetime WatchConnectivityManager owns
    /// this sender. Tests injecting a mock transport must keep it alive for
    /// the sender's whole lifetime.
    private unowned let transport: ExerciseCatalogTransporting
    private let challengeLogger: (String) -> Void

    private(set) var state = ExerciseCatalogSenderState()
    /// Latest challenge reported by the watch (delegate delivery or
    /// receivedApplicationContext). In-memory only — WCSession re-delivers
    /// receivedApplicationContext after relaunch.
    private(set) var currentChallenge: WatchCatalogChallenge?

    /// Snapshot IDs handed to the transport in this process — suppresses
    /// duplicate enqueues of identical requests. Empty at launch, so the
    /// persisted staged snapshot is naturally re-enqueued once per iOS launch.
    private var enqueuedSnapshotIDs: Set<UUID> = []
    /// Bounded, non-recursive transient-failure retry bookkeeping.
    private var retryAttempts: [UUID: Int] = [:]
    private static let maxTransientRetries = 3

    /// Deterministic bytes: identical snapshot values encode identically.
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    init(
        transport: ExerciseCatalogTransporting,
        directory: URL? = nil,
        challengeLogger: @escaping (String) -> Void = { print($0) }
    ) {
        self.transport = transport
        self.challengeLogger = challengeLogger
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ExerciseCatalogSync", isDirectory: true)
        self.directory = base
        self.stagingDirectory = base.appendingPathComponent("Staging", isDirectory: true)
        self.stateFileURL = base.appendingPathComponent("state.json")
        try? FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        loadState()
    }

    // MARK: - Inputs

    /// New desired catalogue content from the sync coordinator. Identical
    /// content is suppressed unless it still needs (re-)enqueueing.
    func requestSync(items: [WatchExerciseCatalogItem]) {
        if state.desiredItems != items {
            var newState = state
            newState.desiredItems = items
            newState.blockedSnapshotID = nil // changed content unblocks a poisoned representation
            guard persist(newState) else {
                print("CatalogSync: state write failed — enqueueing nothing")
                return
            }
        }
        attemptSend()
    }

    /// Watch → iOS applicationContext arrived (delegate or post-activation
    /// read). Promotes a proposed authority the watch has accepted, recovers
    /// the generation high-water mark, and restages if needed.
    func updateChallenge(fromApplicationContext context: [String: Any]) {
        guard let challenge = WatchCatalogChallenge(applicationContext: context) else { return }
        let isNewChallenge = currentChallenge != challenge
        currentChallenge = challenge
        if isNewChallenge {
            challengeLogger(
                "CatalogSync: challenge from watch \(challenge.watchInstanceID) — epoch \(challenge.currentEpoch?.uuidString ?? "bootstrap"), generation \(challenge.currentGeneration)"
            )
        }

        var newState = state
        if let proposal = newState.proposedAuthority, challenge.currentEpoch == proposal.epoch {
            // The watch accepted our handover — the proposal is now the authority.
            newState.activeAuthorityEpoch = proposal.epoch
            newState.nextGeneration = challenge.currentGeneration + 1
            newState.proposedAuthority = nil
        }
        if let active = newState.activeAuthorityEpoch, challenge.currentEpoch == active {
            // Recover restored/older sender state: never allocate at or below
            // the receiver's high-water generation.
            if challenge.currentGeneration >= newState.nextGeneration {
                newState.nextGeneration = challenge.currentGeneration + 1
            }
            newState.proposedAuthority = nil
        }
        if !persistIfChanged(newState) { return }
        attemptSend()
    }

    /// Session activated with a paired/installed watch, or the watch
    /// state/instance changed. Re-enqueues the latest staged snapshot.
    func sessionDidBecomeReady() {
        attemptSend()
    }

    /// `session(_:didFinish:error:)` outcome for a catalogue transfer.
    func transferDidFinish(fileURL: URL, snapshotID: UUID?, error: Error?) {
        defer { try? FileManager.default.removeItem(at: fileURL) }
        guard let snapshotID else { return }

        guard let error else {
            retryAttempts[snapshotID] = nil
            print("CatalogSync: transfer completed for snapshot \(snapshotID)")
            return
        }

        // A superseded (cancelled) snapshot must never requeue itself.
        guard snapshotID == state.stagedSnapshot?.snapshotID else {
            print("CatalogSync: superseded snapshot \(snapshotID) finished with \(error.localizedDescription) — dropped")
            return
        }

        if Self.isTerminalForBytes(error) {
            markBlocked(snapshotID, reason: error.localizedDescription)
            return
        }

        // Transient: the durable desired/staged state stays replayable.
        enqueuedSnapshotIDs.remove(snapshotID)
        let attempt = (retryAttempts[snapshotID] ?? 0) + 1
        retryAttempts[snapshotID] = attempt
        print("CatalogSync: transient transfer failure for \(snapshotID) (attempt \(attempt)) — \(error.localizedDescription)")
        guard attempt <= Self.maxTransientRetries else { return } // lifecycle triggers still retry later
        let delay = Duration.seconds(1 << attempt)
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.state.stagedSnapshot?.snapshotID == snapshotID else { return }
            self.attemptSend()
        }
    }

    /// Launch-time cleanup: removes staging files no longer referenced by any
    /// outstanding transfer. URLs still owned by WCSession are kept alive.
    func cleanUpOrphanedStagingFiles(keeping referencedURLs: [URL]) {
        let referenced = Set(referencedURLs.map(\.standardizedFileURL.path))
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: stagingDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in contents where !referenced.contains(url.standardizedFileURL.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Staging

    private func attemptSend() {
        guard let desired = state.desiredItems else { return }
        guard let challenge = currentChallenge else {
            // Retain the desired catalogue; sending without a receiver
            // challenge would be an unauthorized/untargetable snapshot.
            return
        }

        // The challenge proves the watch already accepted this exact content
        // (same authority, generation at or above the staged snapshot) —
        // nothing to send.
        if let staged = state.stagedSnapshot, staged.items == desired,
           let active = state.activeAuthorityEpoch,
           challenge.currentEpoch == active,
           staged.authorityEpoch == active,
           staged.generation <= challenge.currentGeneration {
            return
        }

        let snapshot: WatchExerciseCatalogSnapshot
        if let staged = state.stagedSnapshot, staged.items == desired, isStagedValid(staged, for: challenge) {
            snapshot = staged // exact same epoch/generation/bytes for ordinary retries
        } else if let fresh = stage(items: desired, for: challenge) {
            snapshot = fresh
        } else {
            return
        }

        guard snapshot.snapshotID != state.blockedSnapshotID else {
            print("CatalogSync: snapshot \(snapshot.snapshotID) is blocked (terminal failure) — waiting for content change")
            return
        }
        enqueue(snapshot)
    }

    /// Whether the persisted staged snapshot is still authorized under the
    /// watch's current challenge.
    private func isStagedValid(_ staged: WatchExerciseCatalogSnapshot, for challenge: WatchCatalogChallenge) -> Bool {
        if let active = state.activeAuthorityEpoch, challenge.currentEpoch == active {
            return staged.authorityEpoch == active && staged.handoverNonce == nil
        }
        guard let proposal = state.proposedAuthority, proposal.challenge == challenge else { return false }
        return staged.authorityEpoch == proposal.epoch
            && staged.targetWatchInstanceID == challenge.watchInstanceID
            && staged.fromAuthorityEpoch == challenge.currentEpoch
            && staged.handoverNonce == challenge.handoverNonce
    }

    /// Allocates epoch/generation for the desired content, persists the
    /// complete sender state, and returns the staged snapshot. Returns nil
    /// (enqueueing nothing) when the state write fails.
    private func stage(items: [WatchExerciseCatalogItem], for challenge: WatchCatalogChallenge) -> WatchExerciseCatalogSnapshot? {
        var newState = state
        let snapshot: WatchExerciseCatalogSnapshot

        let sameAuthority = newState.activeAuthorityEpoch != nil
            && challenge.currentEpoch == newState.activeAuthorityEpoch
            && challenge.currentGeneration < UInt64.max // overflow rolls into an authorized handover

        if sameAuthority, let active = newState.activeAuthorityEpoch {
            let generation = max(newState.nextGeneration, challenge.currentGeneration + 1)
            snapshot = WatchExerciseCatalogSnapshot(
                schemaVersion: WatchExerciseCatalogSync.schemaVersion,
                authorityEpoch: active,
                generation: generation,
                snapshotID: UUID(),
                targetWatchInstanceID: nil,
                fromAuthorityEpoch: nil,
                handoverNonce: nil,
                items: items
            )
            newState.nextGeneration = generation + 1
            newState.proposedAuthority = nil
        } else {
            // Bootstrap or authority handover: a fresh proposed epoch bound to
            // the exact challenge tuple. A previously persisted mismatching
            // authority may already be retired by this watch — never re-propose it.
            let epoch: UUID
            var generation: UInt64 = 1
            if let proposal = newState.proposedAuthority, proposal.challenge == challenge {
                epoch = proposal.epoch
                if let staged = newState.stagedSnapshot, staged.authorityEpoch == epoch {
                    generation = staged.generation + 1 // content changed under the outstanding proposal
                }
            } else {
                epoch = UUID()
                newState.proposedAuthority = .init(epoch: epoch, challenge: challenge)
            }
            snapshot = WatchExerciseCatalogSnapshot(
                schemaVersion: WatchExerciseCatalogSync.schemaVersion,
                authorityEpoch: epoch,
                generation: generation,
                snapshotID: UUID(),
                targetWatchInstanceID: challenge.watchInstanceID,
                fromAuthorityEpoch: challenge.currentEpoch,
                handoverNonce: challenge.handoverNonce,
                items: items
            )
        }

        newState.desiredItems = items
        newState.stagedSnapshot = snapshot
        newState.blockedSnapshotID = nil
        guard persist(newState) else {
            print("CatalogSync: state write failed — enqueueing nothing")
            return nil
        }
        return snapshot
    }

    private func enqueue(_ snapshot: WatchExerciseCatalogSnapshot) {
        guard transport.isReadyForCatalogTransfer else { return } // staged state is retained for lifecycle retries
        guard !enqueuedSnapshotIDs.contains(snapshot.snapshotID) else { return }

        let fileURL = stagingDirectory.appendingPathComponent("\(snapshot.snapshotID.uuidString).json")
        let data: Data
        do {
            data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Local encode/write failure is terminal for this representation.
            markBlocked(snapshot.snapshotID, reason: error.localizedDescription)
            return
        }

        // Map/encode/validate happened above — only now prune the queue, then
        // immediately enqueue the replacement.
        transport.cancelOutstandingCatalogTransfers()
        transport.transferCatalogFile(at: fileURL, metadata: [
            WatchExerciseCatalogSync.metadataTypeKey: WatchExerciseCatalogSync.metadataTypeValue,
            WatchExerciseCatalogSync.metadataSnapshotIDKey: snapshot.snapshotID.uuidString
        ])
        enqueuedSnapshotIDs.insert(snapshot.snapshotID)
        print("CatalogSync: enqueued snapshot \(snapshot.snapshotID) — \(snapshot.items.count) items, \(data.count) bytes, epoch \(snapshot.authorityEpoch), generation \(snapshot.generation)")
    }

    // MARK: - Failure classification

    /// Errors that poison these exact bytes for the current build — retrying
    /// the identical payload can never succeed. Apple documents no complete
    /// permanent/transient taxonomy, so this is deliberate app policy; unknown
    /// errors stay transient (bounded lifecycle retries).
    private static func isTerminalForBytes(_ error: Error) -> Bool {
        guard let wcError = error as? WCError else { return false }
        switch wcError.code {
        case .payloadTooLarge, .payloadUnsupportedTypes, .invalidParameter:
            return true
        default:
            return false
        }
    }

    private func markBlocked(_ snapshotID: UUID, reason: String) {
        var newState = state
        newState.blockedSnapshotID = snapshotID
        _ = persist(newState)
        print("CatalogSync: snapshot \(snapshotID) terminally failed — \(reason). Blocked until the catalogue changes.")
    }

    // MARK: - State persistence

    private func loadState() {
        guard let data = try? Data(contentsOf: stateFileURL) else { return }
        do {
            state = try JSONDecoder().decode(ExerciseCatalogSenderState.self, from: data)
        } catch {
            print("CatalogSync: failed to decode sender state — starting fresh (\(error.localizedDescription))")
        }
    }

    /// Atomically replaces the state file and adopts the new state. Returns
    /// false (leaving in-memory state untouched) when the write fails.
    @discardableResult
    private func persist(_ newState: ExerciseCatalogSenderState) -> Bool {
        do {
            let data = try encoder.encode(newState)
            try data.write(to: stateFileURL, options: .atomic)
            state = newState
            return true
        } catch {
            print("CatalogSync: failed to persist sender state — \(error.localizedDescription)")
            return false
        }
    }

    private func persistIfChanged(_ newState: ExerciseCatalogSenderState) -> Bool {
        let changed = (try? encoder.encode(newState)) != (try? encoder.encode(state))
        return changed ? persist(newState) : true
    }
}
