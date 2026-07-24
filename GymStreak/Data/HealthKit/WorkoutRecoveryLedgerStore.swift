//
//  WorkoutRecoveryLedgerStore.swift
//  GymStreak
//
//  Durable persistence for the HealthKit recovery ledger (ticket 09 of
//  in-workout routine editing). One tiny JSON file per external UUID in the
//  App Group container — append-only with O(1) lookup by filename, the same
//  representation choice as `WorkoutIngestReceiptStore` and for the same
//  reason: candidates must survive relaunches and stale WatchConnectivity
//  delivery has no published lifetime bound.
//
//  The ledger is also the `HKObject.uuid → externalUUID` correlation table the
//  anchored-query DELETE path requires: `HKDeletedObject` exposes only the
//  HealthKit object UUID (its external-UUID metadata is not preserved), so a
//  deletion is mapped back to a candidate by scanning the persisted object-UUID
//  sets. Kept strictly separate from authoritative routine/template state.
//
//  Discovery and deletion apply idempotently: re-observing the same
//  (externalUUID, objectUUID) is a no-op, so an anchored-query replay after a
//  crash never duplicates or corrupts a candidate.
//

import Foundation

/// The facts an anchored-query added HKWorkout contributes to the ledger.
struct DiscoveredWorkoutFacts: Sendable {
    let externalUUID: UUID
    let healthKitObjectUUID: UUID
    let startDate: Date
    let endDate: Date
    let activeEnergyKilocalories: Double?
    let routineName: String
    let routineId: UUID?
    let fromWatch: Bool
}

@MainActor
final class WorkoutRecoveryLedgerStore {
    private let directory: URL?

    /// - Parameter directory: override for tests; defaults to the App Group's
    ///   HealthKitRecovery/Ledger directory.
    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WatchWorkoutInboxStore.appGroupID)?
            .appendingPathComponent("HealthKitRecovery/Ledger", isDirectory: true)
        self.directory = base
        if let base {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
    }

    // MARK: - Reads

    func entries() -> [WorkoutRecoveryLedgerEntry] {
        guard let directory,
              let urls = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
              ) else { return [] }
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { decode($0) }
    }

    func entry(forExternalUUID externalUUID: UUID) -> WorkoutRecoveryLedgerEntry? {
        decode(url(for: externalUUID))
    }

    // MARK: - Idempotent discovery / deletion

    /// Applies one added HKWorkout to the ledger and returns the resulting
    /// entry. Idempotent: re-applying the same (externalUUID, objectUUID)
    /// leaves the entry byte-identical. A second, DIFFERENT object UUID for the
    /// same external UUID is unioned in — which the reconciler then treats as a
    /// diagnosed conflict rather than duplicate history.
    @discardableResult
    func applyDiscovered(_ facts: DiscoveredWorkoutFacts, now: Date) throws -> WorkoutRecoveryLedgerEntry {
        var entry = entry(forExternalUUID: facts.externalUUID) ?? WorkoutRecoveryLedgerEntry(
            externalUUID: facts.externalUUID,
            startDate: facts.startDate,
            endDate: facts.endDate,
            activeEnergyKilocalories: facts.activeEnergyKilocalories,
            routineName: facts.routineName,
            routineId: facts.routineId,
            fromWatch: facts.fromWatch,
            discoveredAt: now
        )
        entry.healthKitObjectUUIDs.insert(facts.healthKitObjectUUID)
        // A re-added object that was previously tombstoned returns to
        // provisional (HealthKit re-synced it); terminal history states stand.
        if entry.state == .tombstoned {
            entry.state = .provisional
            entry.deletedAt = nil
        }
        try upsert(entry)
        return entry
    }

    /// Maps a HealthKit deletion (object UUID only) back to its candidate and
    /// removes that object from the correlation. When a candidate loses its
    /// last HealthKit object it is tombstoned (a deleted workout is never
    /// offered for recovery). Idempotent and safe for an unknown UUID.
    @discardableResult
    func applyDeleted(objectUUID: UUID, now: Date) -> WorkoutRecoveryLedgerEntry? {
        guard var entry = entries().first(where: { $0.healthKitObjectUUIDs.contains(objectUUID) }) else {
            return nil
        }
        entry.healthKitObjectUUIDs.remove(objectUUID)
        entry.deletedAt = now
        if entry.healthKitObjectUUIDs.isEmpty {
            entry.state = .tombstoned
        }
        try? upsert(entry)
        return entry
    }

    // MARK: - Writes

    /// Atomically persists an entry, replacing any prior version in place.
    /// Throws so the caller can keep the anchor unadvanced and replay.
    func upsert(_ entry: WorkoutRecoveryLedgerEntry) throws {
        guard let url = url(for: entry.externalUUID) else { throw CocoaError(.fileNoSuchFile) }
        let data = try JSONEncoder().encode(entry)
        try data.write(to: url, options: .atomic)
    }

    func remove(externalUUID: UUID) {
        guard let url = url(for: externalUUID) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Helpers

    private func url(for externalUUID: UUID) -> URL? {
        directory?.appendingPathComponent("\(externalUUID.uuidString).json")
    }

    private func decode(_ url: URL?) -> WorkoutRecoveryLedgerEntry? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WorkoutRecoveryLedgerEntry.self, from: data)
    }
}
