//
//  WatchWorkoutInboxStore.swift
//  GymStreak
//
//  Durable receive inbox for completed watch workouts (ticket 04, in-workout
//  routine editing). Replaces the former `pendingReceivedWorkouts`
//  UserDefaults blob (migrated on first init, order preserved) —
//  `UserDefaults.set` plus readback is not crash-persistence proof, and
//  WatchConnectivity receive callbacks establish neither app persistence nor
//  a SwiftData commit. Both `sendMessage` and `transferUserInfo` deliveries
//  enter through this one boundary: the exact payload bytes are written
//  atomically (one file per workout, arrival-ordered filenames) BEFORE any
//  ingestion, notification, or acknowledgment happens.
//
//  Malformed files are moved to a Quarantine directory (diagnosed, never
//  replayed, last-good data unaffected); transient read/write failures leave
//  entries replayable. Entries are removed only by the ingestion coordinator
//  once their terminal receipt is durable.
//

import Foundation

@MainActor
final class WatchWorkoutInboxStore {
    struct Entry {
        let url: URL
        let transaction: TemplateTransactionEnvelope?
        let legacyWorkout: CompletedWatchWorkout?

        var completedWorkout: CompletedWatchWorkout? {
            transaction?.completedWorkout ?? legacyWorkout
        }

        var transactionKey: TemplateTransactionKey? { transaction?.key }
        var identifier: UUID { transaction?.transactionID ?? legacyWorkout!.id }
    }

    nonisolated static let appGroupID = "group.com.gymstreak.shared"
    nonisolated static let legacyDefaultsKey = "pendingReceivedWorkouts"

    private let inboxDirectory: URL?
    private let quarantineDirectory: URL?

    /// - Parameters:
    ///   - directory: override for tests; defaults to the App Group's
    ///     WatchWorkoutSync directory.
    ///   - legacyDefaults: source of the pre-ticket-04 UserDefaults buffer,
    ///     migrated (order preserved) on first init.
    init(
        directory: URL? = nil,
        legacyDefaults: UserDefaults? = UserDefaults(suiteName: WatchWorkoutInboxStore.appGroupID)
    ) {
        let base = directory ?? FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)?
            .appendingPathComponent("WatchWorkoutSync", isDirectory: true)
        self.inboxDirectory = base?.appendingPathComponent("Inbox", isDirectory: true)
        self.quarantineDirectory = base?.appendingPathComponent("Quarantine", isDirectory: true)
        if let inboxDirectory {
            try? FileManager.default.createDirectory(at: inboxDirectory, withIntermediateDirectories: true)
        }
        migrateLegacyEntries(from: legacyDefaults)
    }

    // MARK: - Writing

    /// Atomically persists the exact received payload bytes. A duplicate
    /// delivery of an already-inboxed workout id keeps the original entry and
    /// its arrival position. Throws when the write fails — the caller must
    /// then NOT acknowledge, so the watch's durable queue redelivers.
    func store(payloadData: Data, workoutId: UUID) throws {
        try store(data: payloadData, identifier: workoutId)
    }

    /// Persists a generic template transaction. Its semantic transaction id,
    /// not optional workout correlation, owns deduplication and file naming.
    func store(transactionData: Data, transactionID: UUID) throws {
        let transaction = try JSONDecoder().decode(TemplateTransactionEnvelope.self, from: transactionData)
        guard transaction.transactionID == transactionID,
              transaction.isInternallyConsistent else {
            throw CocoaError(.coderInvalidValue)
        }
        try store(data: transactionData, identifier: transactionID)
    }

    private func store(data: Data, identifier: UUID) throws {
        guard let inboxDirectory else { throw CocoaError(.fileNoSuchFile) }
        guard !containsEntry(for: identifier) else { return }
        let name = String(format: "%017.6f", Date().timeIntervalSince1970)
            + "-\(identifier.uuidString).json"
        try data.write(to: inboxDirectory.appendingPathComponent(name), options: .atomic)
    }

    /// Removes a processed entry. Best effort: a leftover entry is answered
    /// from its terminal receipt on the next drain, so removal converges.
    func remove(_ entry: Entry) {
        try? FileManager.default.removeItem(at: entry.url)
    }

    // MARK: - Reading

    func containsEntry(for workoutId: UUID) -> Bool {
        fileURLs().contains { $0.lastPathComponent.contains(workoutId.uuidString) }
    }

    /// Decoded entries, oldest first. Undecodable files are quarantined with
    /// diagnostics; unreadable files stay replayable for the next drain.
    func entries() -> [Entry] {
        fileURLs().compactMap { url in
            guard let data = try? Data(contentsOf: url) else {
                print("WatchWorkoutInboxStore: could not read \(url.lastPathComponent) — will retry")
                return nil
            }
            do {
                if let transaction = try? JSONDecoder().decode(TemplateTransactionEnvelope.self, from: data) {
                    return Entry(url: url, transaction: transaction, legacyWorkout: nil)
                }
                let workout = try JSONDecoder().decode(CompletedWatchWorkout.self, from: data)
                return Entry(url: url, transaction: nil, legacyWorkout: workout)
            } catch {
                quarantine(url, error: error)
                return nil
            }
        }
    }

    private func fileURLs() -> [URL] {
        guard let inboxDirectory else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(
            at: inboxDirectory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func quarantine(_ url: URL, error: Error) {
        print("WatchWorkoutInboxStore: malformed payload \(url.lastPathComponent) — \(error.localizedDescription). Quarantined.")
        guard let quarantineDirectory else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.createDirectory(at: quarantineDirectory, withIntermediateDirectories: true)
        do {
            try FileManager.default.moveItem(
                at: url,
                to: quarantineDirectory.appendingPathComponent(url.lastPathComponent)
            )
        } catch {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Legacy migration

    /// Migrates the pre-ticket-04 UserDefaults array into inbox files without
    /// reordering: index-prefixed names sort before every live arrival
    /// timestamp, keeping legacy entries at the front. The blob is removed
    /// only after every file write succeeded; on failure it stays the
    /// recovery source and migration re-runs next launch (id-deduped).
    private func migrateLegacyEntries(from defaults: UserDefaults?) {
        guard let defaults,
              let data = defaults.data(forKey: Self.legacyDefaultsKey),
              let legacy = try? JSONDecoder().decode([CompletedWatchWorkout].self, from: data),
              !legacy.isEmpty,
              let inboxDirectory else { return }
        do {
            for (index, workout) in legacy.enumerated() where !containsEntry(for: workout.id) {
                let payload = try JSONEncoder().encode(workout)
                let name = String(format: "%017.6f", Double(index) / 1_000_000)
                    + "-\(workout.id.uuidString).json"
                try payload.write(to: inboxDirectory.appendingPathComponent(name), options: .atomic)
            }
            defaults.removeObject(forKey: Self.legacyDefaultsKey)
            print("WatchWorkoutInboxStore: migrated \(legacy.count) legacy buffered workout(s)")
        } catch {
            print("WatchWorkoutInboxStore: legacy migration failed — \(error.localizedDescription); keeping legacy blob")
        }
    }
}
