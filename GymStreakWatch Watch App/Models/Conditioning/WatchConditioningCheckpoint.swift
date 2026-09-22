//
//  WatchConditioningCheckpoint.swift
//  GymStreakWatch Watch App
//
//  The crash boundary of a running watch conditioning session (ticket 06,
//  docs/fight-conditioning.md). Everything needed to resume it on relaunch:
//  the session as synced, the chosen modality, the pause-aware clock and the
//  Apple Health external UUID. Written on start, pause and resume only — the
//  clock is wall-clock based, so nothing per tick needs saving.
//

import Foundation

struct WatchConditioningCheckpoint: Codable, Equatable {
    let session: WatchConditioningSession
    let modality: String
    var clock: ConditioningClock
    let externalUUID: UUID
}

/// One atomically-replaced App Group file, the same discipline as
/// `WatchActiveWorkoutCheckpointStore`; an undecodable file is treated as none.
final class WatchConditioningCheckpointStore {
    private let fileURL: URL?

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WatchActiveWorkoutCheckpointStore.appGroupID)?
            .appendingPathComponent("Conditioning", isDirectory: true)
        if let base { try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true) }
        self.fileURL = base?.appendingPathComponent("active-session-checkpoint.json")
    }

    func load() -> WatchConditioningCheckpoint? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(WatchConditioningCheckpoint.self, from: data)
    }

    /// Best effort: a failed write costs at most crash-resume fidelity, never the session.
    func save(_ checkpoint: WatchConditioningCheckpoint) {
        guard let fileURL, let data = try? JSONEncoder().encode(checkpoint) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
