//
//  WatchExerciseCatalogModels.swift
//  GymStreak
//
//  Wire contract for the iOS → watch exercise-catalogue sync (ticket 03,
//  in-workout routine editing). This file exists as an identical copy in both
//  targets (GymStreak/Data/Sync and GymStreakWatch Watch App/Models) — the
//  project shares types between targets via duplicated files, not target
//  membership. Keep both copies in sync.
//
//  The receiver state machine lives here (not in the watch-only store) so the
//  iOS unit-test target can cover the accept/reject rules through its copy —
//  there is no watch unit-test target.
//

import Foundation

// MARK: - Wire types

/// Full-replacement snapshot of the iOS exercise library. iOS is the source of
/// truth; the watch persists the last valid snapshot. Versioned so unsupported
/// future schemas are rejected instead of misparsed.
struct WatchExerciseCatalogSnapshot: Codable, Sendable {
    /// Starts at 1; the receiver rejects unsupported versions.
    let schemaVersion: Int
    /// Persistent iOS catalogue authority. Recency is only comparable within
    /// one authority epoch; an unknown epoch requires a receiver-authorized
    /// handover (see `WatchExerciseCatalogReceiverState`).
    let authorityEpoch: UUID
    /// Monotonically increases within `authorityEpoch`.
    let generation: UInt64
    /// Identity for diagnostics and duplicate-delivery suppression — never an
    /// ordering mechanism (random UUIDs are not orderable).
    let snapshotID: UUID
    /// Set only on handover/bootstrap snapshots: the watch instance this
    /// authority proposal is addressed to.
    let targetWatchInstanceID: UUID?
    /// The receiver's current epoch this handover moves away from.
    /// nil only for receiver-authorized bootstrap (watch has no catalogue yet).
    let fromAuthorityEpoch: UUID?
    /// Required only for epoch/bootstrap handover; must match the receiver's
    /// persisted unused nonce.
    let handoverNonce: UUID?
    let items: [WatchExerciseCatalogItem]
}

struct WatchExerciseCatalogItem: Codable, Sendable, Hashable {
    /// Exercise.id
    let id: UUID
    /// Stable identity of a seeded exercise; nil for user-created exercises.
    /// The launch seeder can deduplicate seeded rows and change the surviving
    /// Exercise.id, so tickets 06/07 need this as fallback identity.
    let seedKey: String?
    let name: String
    let muscleGroups: [String]
    /// The watch has no EquipmentType/ExerciseLoadBehavior types; raw values
    /// are the explicit compatibility boundary.
    let equipmentTypeRaw: String
    let loadBehaviorRaw: String
}

// MARK: - Transfer + application-context keys

/// Transfer/context key constants — read from the `nonisolated`
/// `session(_:didReceive:)` callback to route incoming files, so the type opts
/// out of the watch target's default main-actor isolation. All members are
/// immutable `Sendable` constants. (In the iOS copy this is a harmless no-op — that target defaults to
/// nonisolated — but the two files are kept identical so they stay diffable.)
nonisolated enum WatchExerciseCatalogSync {
    static let schemaVersion = 1

    /// `WCSessionFile.metadata` tag identifying catalogue transfers; used to
    /// route received files and to cancel only superseded catalogue transfers.
    static let metadataTypeKey = "type"
    static let metadataTypeValue = "exerciseCatalog"
    static let metadataSnapshotIDKey = "snapshotID"

    /// Watch → iOS applicationContext keys publishing the receiver challenge.
    /// All values are Strings (UUID strings / decimal UInt64) — plists cannot
    /// portably hold the full UInt64 range. These keys must be MERGED into the
    /// watch's complete context dictionary: updateApplicationContext replaces
    /// the whole dictionary per direction.
    static let contextWatchInstanceIDKey = "catalogueWatchInstanceID"
    static let contextCurrentEpochKey = "catalogueCurrentEpoch"
    static let contextCurrentGenerationKey = "catalogueCurrentGeneration"
    static let contextHandoverNonceKey = "catalogueHandoverNonce"
}

// MARK: - Receiver state machine

/// The watch's persisted catalogue acceptance state — one atomically replaced
/// Codable state file. `items == nil` means "never received a catalogue";
/// `items == []` means "iOS library is currently (validly) empty".
struct WatchExerciseCatalogReceiverState: Codable {
    /// Stable identity of this watch install; handover snapshots must target it.
    var watchInstanceID: UUID
    /// Authority epoch of the last accepted snapshot; nil until bootstrap.
    var acceptedEpoch: UUID?
    /// High-water generation within `acceptedEpoch`.
    var acceptedGeneration: UInt64
    /// One stable UNUSED nonce; consumed and re-minted only in the same commit
    /// that accepts a handover. Never rotates on launch or retry.
    var handoverNonce: UUID
    /// Every epoch this watch has moved away from — rejected forever.
    var retiredEpochs: [UUID]
    /// Last accepted catalogue; nil distinguishes never-synced from valid-empty.
    var items: [WatchExerciseCatalogItem]?
    var lastSnapshotID: UUID?
    var lastSyncDate: Date?

    var hasReceivedCatalog: Bool { items != nil }

    /// Fresh state for a new watch install.
    static func initial() -> WatchExerciseCatalogReceiverState {
        WatchExerciseCatalogReceiverState(
            watchInstanceID: UUID(),
            acceptedEpoch: nil,
            acceptedGeneration: 0,
            handoverNonce: UUID(),
            retiredEpochs: [],
            items: nil,
            lastSnapshotID: nil,
            lastSyncDate: nil
        )
    }

    /// The challenge the watch publishes to iOS via applicationContext.
    var challengeContext: [String: String] {
        var context: [String: String] = [
            WatchExerciseCatalogSync.contextWatchInstanceIDKey: watchInstanceID.uuidString,
            WatchExerciseCatalogSync.contextCurrentGenerationKey: String(acceptedGeneration),
            WatchExerciseCatalogSync.contextHandoverNonceKey: handoverNonce.uuidString
        ]
        if let acceptedEpoch {
            context[WatchExerciseCatalogSync.contextCurrentEpochKey] = acceptedEpoch.uuidString
        }
        return context
    }

    enum Decision: Equatable {
        /// Apply the snapshot. `isHandover` == true when it changes the
        /// accepted epoch (bootstrap or authority handover).
        case apply(isHandover: Bool)
        /// Exact snapshot already applied — delete the delivery, change nothing.
        case duplicate
        /// Terminally invalid for this receiver — quarantine/delete, keep cache.
        case reject(RejectionReason)
    }

    enum RejectionReason: String, Equatable {
        case unsupportedSchema
        case staleGeneration
        /// Same epoch and generation as the accepted snapshot but a different
        /// snapshotID — conflicting content that recency cannot order.
        case conflictingEqualGeneration
        case retiredEpoch
        case wrongTargetWatch
        case wrongFromEpoch
        case wrongNonce
    }

    func decision(for snapshot: WatchExerciseCatalogSnapshot) -> Decision {
        guard snapshot.schemaVersion == WatchExerciseCatalogSync.schemaVersion else {
            return .reject(.unsupportedSchema)
        }
        if let lastSnapshotID, snapshot.snapshotID == lastSnapshotID {
            return .duplicate
        }
        if let acceptedEpoch, snapshot.authorityEpoch == acceptedEpoch {
            // Within the current authority only a strictly higher generation wins.
            if snapshot.generation > acceptedGeneration {
                return .apply(isHandover: false)
            }
            if snapshot.generation == acceptedGeneration {
                return .reject(.conflictingEqualGeneration)
            }
            return .reject(.staleGeneration)
        }
        // Unknown epoch: acceptable only as a receiver-authorized one-shot handover.
        if retiredEpochs.contains(snapshot.authorityEpoch) {
            return .reject(.retiredEpoch)
        }
        guard snapshot.targetWatchInstanceID == watchInstanceID else {
            return .reject(.wrongTargetWatch)
        }
        guard snapshot.fromAuthorityEpoch == acceptedEpoch else {
            return .reject(.wrongFromEpoch)
        }
        guard snapshot.handoverNonce == handoverNonce else {
            return .reject(.wrongNonce)
        }
        return .apply(isHandover: true)
    }

    /// Applies an authorized snapshot. Caller must have obtained
    /// `.apply(isHandover:)` from `decision(for:)` and must persist the mutated
    /// state atomically in the same commit (epoch change, nonce consumption,
    /// and catalogue replacement are one transaction).
    mutating func accept(_ snapshot: WatchExerciseCatalogSnapshot, isHandover: Bool, at date: Date) {
        if isHandover {
            if let acceptedEpoch { retiredEpochs.append(acceptedEpoch) }
            acceptedEpoch = snapshot.authorityEpoch
            // Consume the one-shot nonce and mint the next in the same commit.
            handoverNonce = UUID()
        }
        acceptedGeneration = snapshot.generation
        items = snapshot.items
        lastSnapshotID = snapshot.snapshotID
        lastSyncDate = date
    }
}
