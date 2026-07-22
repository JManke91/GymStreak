//
//  ExerciseCatalogSenderState.swift
//  GymStreak
//
//  Persisted iOS-side state and transport seam for the exercise-catalogue
//  sync (see ExerciseCatalogSender.swift and docs/watch-sync.md).
//

import Foundation

// MARK: - Transport seam

/// What `ExerciseCatalogSender` needs from WCSession. Implemented by
/// `WatchConnectivityManager`; tests inject a recording double.
@MainActor
protocol ExerciseCatalogTransporting: AnyObject {
    /// Activated session with a paired watch whose Watch app is installed.
    /// Reachability is deliberately NOT part of this — file transfers queue
    /// without it.
    var isReadyForCatalogTransfer: Bool { get }
    /// Cancels only outstanding file transfers whose metadata tag is
    /// `type == "exerciseCatalog"`.
    func cancelOutstandingCatalogTransfers()
    func transferCatalogFile(at url: URL, metadata: [String: Any])
}

// MARK: - Receiver challenge (watch → iOS applicationContext)

/// The watch's published catalogue acceptance state. iOS may only send a
/// snapshot that this challenge authorizes: same-epoch sends need the
/// reported epoch, handovers need the exact tuple below.
struct WatchCatalogChallenge: Codable, Equatable {
    let watchInstanceID: UUID
    /// nil while the watch has never accepted a catalogue (bootstrap).
    let currentEpoch: UUID?
    let currentGeneration: UInt64
    let handoverNonce: UUID

    /// Parses the challenge keys out of a watch → iOS applicationContext
    /// dictionary. Returns nil when the keys are absent (older watch app) or
    /// malformed.
    init?(applicationContext: [String: Any]) {
        guard
            let instanceString = applicationContext[WatchExerciseCatalogSync.contextWatchInstanceIDKey] as? String,
            let instanceID = UUID(uuidString: instanceString),
            let generationString = applicationContext[WatchExerciseCatalogSync.contextCurrentGenerationKey] as? String,
            let generation = UInt64(generationString),
            let nonceString = applicationContext[WatchExerciseCatalogSync.contextHandoverNonceKey] as? String,
            let nonce = UUID(uuidString: nonceString)
        else { return nil }
        self.watchInstanceID = instanceID
        self.currentEpoch = (applicationContext[WatchExerciseCatalogSync.contextCurrentEpochKey] as? String)
            .flatMap(UUID.init(uuidString:))
        self.currentGeneration = generation
        self.handoverNonce = nonce
    }
}

// MARK: - Persisted sender state

/// One atomically replaced Application Support state file. Persisted BEFORE a
/// transfer is enqueued so retries after relaunch reuse the exact same
/// epoch/generation/snapshot bytes.
struct ExerciseCatalogSenderState: Codable {
    /// A fresh authority epoch proposed for a specific receiver challenge; it
    /// becomes active only once the watch republishes it as its current epoch.
    struct ProposedAuthority: Codable, Equatable {
        let epoch: UUID
        /// The exact challenge tuple this proposal is bound to — a changed
        /// tuple must allocate a new proposal.
        let challenge: WatchCatalogChallenge
    }

    /// The authority epoch this sender established with the watch, i.e. the
    /// last epoch the watch reported back as current. nil until bootstrap
    /// completes.
    var activeAuthorityEpoch: UUID?
    /// Next generation to allocate within `activeAuthorityEpoch`.
    var nextGeneration: UInt64 = 1
    var proposedAuthority: ProposedAuthority?
    /// Latest desired catalogue content; nil until the first coordinator
    /// request of this install. Retained across failures so lifecycle
    /// triggers can restage it.
    var desiredItems: [WatchExerciseCatalogItem]?
    /// Latest staged snapshot — the exact value retries re-enqueue.
    var stagedSnapshot: WatchExerciseCatalogSnapshot?
    /// Snapshot whose exact bytes failed terminally (encode failure,
    /// payloadTooLarge, …). Never requeued by lifecycle triggers; cleared
    /// when the catalogue content changes.
    var blockedSnapshotID: UUID?
}
