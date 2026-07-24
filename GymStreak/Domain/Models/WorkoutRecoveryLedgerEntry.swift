//
//  WorkoutRecoveryLedgerEntry.swift
//  GymStreak
//
//  The durable recovery-ledger record (ticket 09 of in-workout routine
//  editing). One entry per HealthKit *external* UUID — the stable cross-device
//  workout identity carried in `HKMetadataKeyExternalUUID` and shared by the
//  watch's HKWorkout, the rich WatchConnectivity payload, and any recovered
//  placeholder. The ledger is app-owned durable state kept *separate* from
//  authoritative routine/template state: it never mutates a routine.
//
//  This is a pure Domain value type (Codable, no framework imports) so the
//  `WorkoutRecoveryReconciler` policy can operate on it and the Data layer can
//  persist it as JSON. HealthKit correlation (external UUID ← HK object UUIDs)
//  is captured here because anchored-query *deleted* objects only expose the
//  HealthKit object UUID, never the external-UUID metadata — so the mapping
//  must be remembered from the added-object phase to interpret a deletion.
//

import Foundation

/// Where an external-UUID candidate sits in the conservative recovery
/// lifecycle. `provisional` is the only state that may ever be surfaced for
/// user-confirmed recovery, and only after the reconciler's gates pass.
enum WorkoutRecoveryState: String, Codable, Sendable {
    /// Discovered in HealthKit; no rich payload or history yet. Awaiting the
    /// grace period / WatchConnectivity delivery. Never auto-reconstructed.
    case provisional
    /// Rich history or a terminal ingest receipt exists for this workout —
    /// nothing to reconstruct. Terminal.
    case resolvedByHistory
    /// A user-confirmed, history-only placeholder was committed. Still
    /// replaceable by a later rich payload (which is why this is not terminal).
    case placeholderSaved
    /// A later rich payload replaced the placeholder with real per-set data.
    /// Terminal.
    case placeholderReplaced
    /// The HealthKit object(s) behind this external UUID were deleted. Terminal.
    case tombstoned
}

/// One recovery candidate, keyed by its HealthKit external UUID.
struct WorkoutRecoveryLedgerEntry: Codable, Equatable, Identifiable, Sendable {
    /// `HKMetadataKeyExternalUUID` — the ledger key and the stable identity
    /// used to correlate HealthKit, the rich payload, and any placeholder.
    let externalUUID: UUID
    var id: UUID { externalUUID }

    /// HealthKit object UUIDs correlated to this external UUID. HealthKit
    /// permits several samples to share one external UUID; more than one here
    /// is a conflict we diagnose and refuse to reconstruct, never a licence to
    /// create duplicate history.
    var healthKitObjectUUIDs: Set<UUID>

    // Candidate facts captured from the HKWorkout, sufficient to build a
    // history-only placeholder without re-querying HealthKit.
    var startDate: Date
    var endDate: Date
    var activeEnergyKilocalories: Double?
    var routineName: String
    var routineId: UUID?
    var fromWatch: Bool

    // Lifecycle bookkeeping (bounded — single timestamps, not unbounded logs).
    var discoveredAt: Date
    var deletedAt: Date?
    var lastReconciledAt: Date?
    /// Last concrete error string from an operation on this candidate (e.g. a
    /// failed placeholder save). Retained for the debug summary only.
    var lastError: String?

    var state: WorkoutRecoveryState

    /// The history session id of a saved placeholder, so a later rich payload
    /// (which the ingestion path materializes under a DIFFERENT session id) is
    /// detectable as a replacement rather than an unrelated row.
    var placeholderSessionId: UUID?

    /// More than one HealthKit object mapped to this external UUID. Diagnosed,
    /// never reconstructed.
    var hasExternalUUIDConflict: Bool { healthKitObjectUUIDs.count > 1 }

    init(
        externalUUID: UUID,
        healthKitObjectUUIDs: Set<UUID> = [],
        startDate: Date,
        endDate: Date,
        activeEnergyKilocalories: Double? = nil,
        routineName: String,
        routineId: UUID? = nil,
        fromWatch: Bool,
        discoveredAt: Date,
        deletedAt: Date? = nil,
        lastReconciledAt: Date? = nil,
        lastError: String? = nil,
        state: WorkoutRecoveryState = .provisional,
        placeholderSessionId: UUID? = nil
    ) {
        self.externalUUID = externalUUID
        self.healthKitObjectUUIDs = healthKitObjectUUIDs
        self.startDate = startDate
        self.endDate = endDate
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.routineName = routineName
        self.routineId = routineId
        self.fromWatch = fromWatch
        self.discoveredAt = discoveredAt
        self.deletedAt = deletedAt
        self.lastReconciledAt = lastReconciledAt
        self.lastError = lastError
        self.state = state
        self.placeholderSessionId = placeholderSessionId
    }
}
