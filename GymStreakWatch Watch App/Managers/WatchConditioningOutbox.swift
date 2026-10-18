//
//  WatchConditioningOutbox.swift
//  GymStreakWatch Watch App
//
//  Conditioning sessions finished on the watch that the iPhone has not yet
//  acknowledged (ticket 07, docs/fight-conditioning.md). Persisted in an
//  atomically-replaced App Group file, so a session survives a relaunch and an
//  iPhone that stays unreachable for days. `WatchConnectivityManager` sends every
//  entry with `transferUserInfo` and removes it only on the iPhone's ack —
//  a finished transfer is not proof the iPhone recorded it.
//
//  Generic over the entry type: mat sessions (positioning ticket 05) use a second
//  instance with its own file, sent by the same transport and removed by the same ack.
//
//  Deliberately not the strength workout queue (`WatchSyncStateStore`): that one
//  carries template transactions, routine sequencing and HealthKit finalization
//  phases, none of which a conditioning session has.
//

import Foundation

typealias WatchConditioningOutbox = WatchSessionOutbox<WatchCompletedConditioningSession>
typealias WatchMatSessionOutbox = WatchSessionOutbox<WatchCompletedMatSession>

extension WatchSessionOutbox where Entry == WatchCompletedConditioningSession {
    convenience init(directory: URL? = nil) { self.init(directory: directory, fileName: "outbox.json") }
}

extension WatchSessionOutbox where Entry == WatchCompletedMatSession {
    convenience init(directory: URL? = nil) { self.init(directory: directory, fileName: "mat-outbox.json") }
}

@MainActor
final class WatchSessionOutbox<Entry: Codable & Identifiable> where Entry.ID == UUID {

    private(set) var pending: [Entry]
    /// Set by the connectivity manager: send right away rather than at the next trigger.
    var onEnqueued: (() -> Void)?

    private let fileURL: URL?

    init(directory: URL?, fileName: String) {
        let base = directory ?? FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WatchActiveWorkoutCheckpointStore.appGroupID)?
            .appendingPathComponent("Conditioning", isDirectory: true)
        if let base { try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true) }
        fileURL = base?.appendingPathComponent(fileName)
        pending = fileURL
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([Entry].self, from: $0) }
            ?? []
    }

    func enqueue(_ session: Entry) {
        guard !pending.contains(where: { $0.id == session.id }) else { return }
        pending.append(session)
        persist()
        onEnqueued?()
    }

    /// The iPhone's ack. Unknown ids (a second ack for the same session) are ignored.
    func acknowledge(id: UUID) {
        guard pending.contains(where: { $0.id == id }) else { return }
        pending.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        guard let fileURL else { return }
        do {
            try JSONEncoder().encode(pending).write(to: fileURL, options: .atomic)
        } catch {
            WatchSyncDiagnostics.error("watch: failed to persist \(fileURL.lastPathComponent) — \(error.localizedDescription)")
        }
    }
}
