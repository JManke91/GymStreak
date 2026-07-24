//
//  WorkoutRecoveryDiagnostics.swift
//  GymStreak
//
//  Privacy-conscious structured diagnostics for the HealthKit recovery
//  pipeline (ticket 09 of in-workout routine editing). Everything is keyed by
//  a SHORTENED, hash-stable token derived from the workout/external/HealthKit
//  identifiers — never the raw UUID, and never exercise names, health metrics,
//  or raw payloads. The tokens are deterministic across launches (an FNV-1a
//  fold, not `Hasher`, which is per-process randomized) so support logs from
//  different sessions correlate, yet they are one-way.
//
//  It also formats the bounded support/debug summary. That summary reports each
//  candidate's best-known pipeline position and deliberately keeps genuinely
//  unknown remote progress as `unknown` — it is never inferred from a false
//  `WCSession.hasContentPending`.
//

import Foundation
import os

enum WorkoutRecoveryDiagnostics {
    private static let logger = Logger(subsystem: "com.shotat24fps.GymStreak", category: "WorkoutRecovery")

    /// Deterministic, one-way 8-hex-char token for a UUID. Stable across app
    /// launches so multi-session support logs correlate.
    static func shortID(_ uuid: UUID) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        withUnsafeBytes(of: uuid.uuid) { bytes in
            for byte in bytes {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01b3
            }
        }
        return String(format: "%08x", UInt32(truncatingIfNeeded: hash))
    }

    // MARK: - Pipeline events

    static func logDrain(discovered: Int, deleted: Int, bootstrap: Bool) {
        logger.info("drain discovered=\(discovered, privacy: .public) deleted=\(deleted, privacy: .public) bootstrap=\(bootstrap, privacy: .public)")
    }

    static func logDrainFailure(_ error: Error) {
        logger.error("drain failed: \(error.localizedDescription, privacy: .public)")
    }

    static func logAnchorReset(reason: String) {
        logger.error("anchor reset (\(reason, privacy: .public)) — rebuilding via idempotent replay")
    }

    static func logDecision(
        externalUUID: UUID,
        summary: WorkoutRecoverySummaryState,
        transportFromWatch: Bool,
        ageSeconds: TimeInterval
    ) {
        logger.info("candidate \(shortID(externalUUID), privacy: .public) state=\(summary.rawValue, privacy: .public) fromWatch=\(transportFromWatch, privacy: .public) age=\(Int(ageSeconds), privacy: .public)s")
    }

    static func logConflict(externalUUID: UUID, objectUUIDs: Set<UUID>) {
        let tokens = objectUUIDs.map(shortID).sorted().joined(separator: ",")
        logger.fault("external-UUID conflict \(shortID(externalUUID), privacy: .public) maps to HK objects [\(tokens, privacy: .public)] — refusing reconstruction")
    }

    static func logPlaceholderSaved(externalUUID: UUID) {
        logger.info("placeholder saved for \(shortID(externalUUID), privacy: .public) (history-only, provisional)")
    }

    static func logPlaceholderSaveFailure(externalUUID: UUID, _ error: Error) {
        logger.error("placeholder save failed for \(shortID(externalUUID), privacy: .public): \(error.localizedDescription, privacy: .public) — candidate stays retryable")
    }

    static func logObserverError(_ error: Error) {
        logger.error("observer error: \(error.localizedDescription, privacy: .public)")
    }

    static func logBackgroundDeliveryUnavailable(_ error: Error) {
        logger.notice("background delivery unavailable (\(error.localizedDescription, privacy: .public)) — foreground drain fallback active")
    }

    // MARK: - Support/debug summary

    /// One bounded line per candidate for the support/debug summary. HealthKit
    /// object UUIDs and the external UUID are shortened; no health content.
    static func summaryLine(
        for entry: WorkoutRecoveryLedgerEntry,
        summary: WorkoutRecoverySummaryState,
        now: Date
    ) -> String {
        let age = Int(now.timeIntervalSince(entry.discoveredAt))
        let objects = entry.healthKitObjectUUIDs.map(shortID).sorted().joined(separator: ",")
        let error = entry.lastError.map { " err=\($0)" } ?? ""
        return "ext=\(shortID(entry.externalUUID)) state=\(summary.rawValue) hk=[\(objects)] fromWatch=\(entry.fromWatch) age=\(age)s\(error)"
    }
}
