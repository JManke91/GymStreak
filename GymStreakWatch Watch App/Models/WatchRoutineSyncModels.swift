//
//  WatchRoutineSyncModels.swift
//  GymStreakWatch Watch App
//
//  Wire contract for the versioned routine sync + template-transaction
//  acknowledgment protocol (ticket 05, in-workout routine editing).
//
//  Routine `applicationContext` snapshots (iOS → watch) carry an authority
//  epoch + generation so a delayed old context can never regress the watch;
//  unknown epochs are accepted only via a receiver-authorized one-shot
//  handover (same principle as the exercise-catalogue sync, ticket 03). The
//  watch publishes its routine challenge in the merged watch → iOS context.
//
//  Template transactions are acknowledged with a versioned terminal ack; a
//  plain legacy `workoutAck` never clears requested-template intent.
//
//  IDENTICAL COPY in both targets — `GymStreak/Data/Sync/` and
//  `GymStreakWatch Watch App/Models/` — keep them in sync. There is no watch
//  unit-test target; the iOS test target covers this logic through its copy.
//

import Foundation

// MARK: - Wire keys

enum WatchRoutineSync {
    /// Protocol version of the template-transaction acknowledgment.
    static let templateUpdateVersion = 1

    // iOS → watch applicationContext keys. Merged into the same dictionary as
    // the legacy "routines" Data payload (updateApplicationContext replaces
    // the whole per-direction dictionary). All values are Strings (UUID
    // strings / decimal UInt64) — plists cannot portably hold UInt64.
    static let contextRoutinesKey = "routines"
    static let contextEpochKey = "routineSyncEpoch"
    static let contextGenerationKey = "routineSyncGeneration"
    static let contextTargetWatchInstanceIDKey = "routineTargetWatchInstanceID"
    static let contextFromEpochKey = "routineFromEpoch"
    static let contextHandoverNonceKey = "routineHandoverNonce"

    // Watch → iOS challenge keys. Must be MERGED with the catalogue challenge
    // keys into the watch's one complete context dictionary.
    static let challengeWatchInstanceIDKey = "routineWatchInstanceID"
    static let challengeCurrentEpochKey = "routineCurrentEpoch"
    static let challengeCurrentGenerationKey = "routineCurrentGeneration"
    static let challengeNonceKey = "routineChallengeNonce"

    // Versioned acknowledgment keys (property-list-safe). `workoutAck`
    // (WatchWorkoutWire.ackKey) stays the workout UUID string so an old watch
    // reads the ack as a plain legacy one.
    static let ackVersionKey = "templateUpdateVersion"
    static let ackTransactionIDKey = "templateTransactionID"
    static let ackOutcomeKey = "templateOutcome"
    static let ackSenderEpochKey = "templateSenderEpoch"
    static let ackSequenceKey = "templateSequence"
    static let ackRoutineEpochKey = "routineSyncEpoch"
    static let ackRoutineGenerationKey = "routineSyncGeneration"
}

// MARK: - Versioned routine snapshot header

enum RoutineSnapshotHeaderParseResult: Equatable {
    case legacy
    case versioned(RoutineSnapshotHeader)
    case malformed
}

/// The authority fields of an iOS → watch routine context.
struct RoutineSnapshotHeader: Equatable {
    let epoch: UUID
    let generation: UInt64
    /// Set only on handover/bootstrap snapshots.
    let targetWatchInstanceID: UUID?
    /// The receiver epoch this handover moves away from; nil only for bootstrap.
    let fromEpoch: UUID?
    let handoverNonce: UUID?

    static func parse(context: [String: Any]) -> RoutineSnapshotHeaderParseResult {
        let hasEpoch = context[WatchRoutineSync.contextEpochKey] != nil
        let hasGeneration = context[WatchRoutineSync.contextGenerationKey] != nil
        guard hasEpoch || hasGeneration else { return .legacy }
        guard hasEpoch, hasGeneration,
              let epochString = context[WatchRoutineSync.contextEpochKey] as? String,
              let epoch = UUID(uuidString: epochString),
              let generationString = context[WatchRoutineSync.contextGenerationKey] as? String,
              let generation = UInt64(generationString) else { return .malformed }

        let optionalUUIDKeys = [
            WatchRoutineSync.contextTargetWatchInstanceIDKey,
            WatchRoutineSync.contextFromEpochKey,
            WatchRoutineSync.contextHandoverNonceKey
        ]
        for key in optionalUUIDKeys where context[key] != nil {
            guard let value = context[key] as? String, UUID(uuidString: value) != nil else {
                return .malformed
            }
        }
        return .versioned(RoutineSnapshotHeader(
            epoch: epoch,
            generation: generation,
            targetWatchInstanceID: (context[WatchRoutineSync.contextTargetWatchInstanceIDKey] as? String)
                .flatMap(UUID.init(uuidString:)),
            fromEpoch: (context[WatchRoutineSync.contextFromEpochKey] as? String)
                .flatMap(UUID.init(uuidString:)),
            handoverNonce: (context[WatchRoutineSync.contextHandoverNonceKey] as? String)
                .flatMap(UUID.init(uuidString:))
        ))
    }

    static func from(context: [String: Any]) -> RoutineSnapshotHeader? {
        guard case .versioned(let header) = parse(context: context) else { return nil }
        return header
    }
}

// MARK: - Watch routine authority (receiver state machine)

/// The watch's persisted routine authority acceptance state. Owned and
/// persisted atomically by the watch workout sync-state owner
/// (`WatchSyncStateStore`) together with the authoritative routine base —
/// epoch change, nonce consumption, and base replacement are one commit.
struct WatchRoutineAuthorityState: Codable, Equatable {
    var watchInstanceID: UUID
    /// Epoch of the last accepted snapshot; nil until bootstrap.
    var acceptedEpoch: UUID?
    /// High-water generation within `acceptedEpoch`.
    var acceptedGeneration: UInt64
    /// One stable UNUSED nonce; consumed and re-minted only in the same commit
    /// that accepts a handover.
    var handoverNonce: UUID
    /// Epochs this watch has moved away from — rejected forever.
    var retiredEpochs: [UUID]

    static func initial() -> WatchRoutineAuthorityState {
        WatchRoutineAuthorityState(
            watchInstanceID: UUID(),
            acceptedEpoch: nil,
            acceptedGeneration: 0,
            handoverNonce: UUID(),
            retiredEpochs: []
        )
    }

    /// The challenge the watch publishes to iOS (merged into the one
    /// watch → iOS context dictionary).
    var challengeContext: [String: String] {
        var context: [String: String] = [
            WatchRoutineSync.challengeWatchInstanceIDKey: watchInstanceID.uuidString,
            WatchRoutineSync.challengeCurrentGenerationKey: String(acceptedGeneration),
            WatchRoutineSync.challengeNonceKey: handoverNonce.uuidString
        ]
        if let acceptedEpoch {
            context[WatchRoutineSync.challengeCurrentEpochKey] = acceptedEpoch.uuidString
        }
        return context
    }

    enum Decision: Equatable {
        case apply(isHandover: Bool)
        /// Same epoch and generation already applied — idempotent redelivery.
        case duplicate
        case reject(String)
    }

    func decision(for header: RoutineSnapshotHeader) -> Decision {
        if let acceptedEpoch, header.epoch == acceptedEpoch {
            if header.generation > acceptedGeneration { return .apply(isHandover: false) }
            if header.generation == acceptedGeneration { return .duplicate }
            return .reject("stale generation \(header.generation) < \(acceptedGeneration)")
        }
        if retiredEpochs.contains(header.epoch) {
            return .reject("retired epoch")
        }
        guard header.targetWatchInstanceID == watchInstanceID else {
            return .reject("handover not targeting this watch")
        }
        guard header.fromEpoch == acceptedEpoch else {
            return .reject("handover from wrong epoch")
        }
        guard header.handoverNonce == handoverNonce else {
            return .reject("handover nonce mismatch")
        }
        return .apply(isHandover: true)
    }

    /// Caller must have obtained `.apply` from `decision(for:)` and must
    /// persist the mutated state atomically in the same commit as the new
    /// routine base.
    mutating func accept(_ header: RoutineSnapshotHeader, isHandover: Bool) {
        if isHandover {
            if let acceptedEpoch { retiredEpochs.append(acceptedEpoch) }
            acceptedEpoch = header.epoch
            handoverNonce = UUID()
        }
        acceptedGeneration = header.generation
    }

    /// Whether the watch has applied the given routine version (same epoch,
    /// generation at or above) — the context half of ack retirement.
    func hasApplied(epoch: UUID, generation: UInt64) -> Bool {
        acceptedEpoch == epoch && acceptedGeneration >= generation
    }
}

// MARK: - Versioned acknowledgment record

/// Parsed versioned template acknowledgment as received on the watch (and as
/// held on a queue entry until the correlated routine context applies).
struct TemplateAckRecord: Codable, Equatable {
    let transactionID: UUID
    /// TemplateTransactionOutcome raw value — kept raw on the watch, which has
    /// no Domain layer.
    let outcomeRaw: String
    let senderEpoch: UUID
    let sequence: UInt64
    let routineEpoch: UUID
    let routineGeneration: UInt64

    static func from(payload: [String: Any]) -> TemplateAckRecord? {
        guard let version = payload[WatchRoutineSync.ackVersionKey] as? String,
              version == String(WatchRoutineSync.templateUpdateVersion),
              let txString = payload[WatchRoutineSync.ackTransactionIDKey] as? String,
              let transactionID = UUID(uuidString: txString),
              let outcomeRaw = payload[WatchRoutineSync.ackOutcomeKey] as? String,
              TemplateTransactionOutcomeWire(rawValue: outcomeRaw) != nil,
              let epochString = payload[WatchRoutineSync.ackSenderEpochKey] as? String,
              let senderEpoch = UUID(uuidString: epochString),
              let sequenceString = payload[WatchRoutineSync.ackSequenceKey] as? String,
              let sequence = UInt64(sequenceString),
              let routineEpochString = payload[WatchRoutineSync.ackRoutineEpochKey] as? String,
              let routineEpoch = UUID(uuidString: routineEpochString),
              let generationString = payload[WatchRoutineSync.ackRoutineGenerationKey] as? String,
              let routineGeneration = UInt64(generationString) else { return nil }
        return TemplateAckRecord(
            transactionID: transactionID,
            outcomeRaw: outcomeRaw,
            senderEpoch: senderEpoch,
            sequence: sequence,
            routineEpoch: routineEpoch,
            routineGeneration: routineGeneration
        )
    }
}
