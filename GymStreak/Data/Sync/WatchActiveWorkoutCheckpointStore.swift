//
//  WatchActiveWorkoutCheckpointStore.swift
//  GymStreakWatch Watch App
//
//  Ticket 08 (in-workout routine editing): a throwing, atomically-replaced App
//  Group file holding the single active-workout checkpoint
//  (`WatchActiveWorkoutCheckpoint`). One file, one workout at a time.
//
//  Mirrors `WatchSyncStateStore`'s persistence discipline: the atomic replace is
//  the crash boundary, and an undecodable file is quarantined as `.corrupt` and
//  treated as "no checkpoint" (the ticket's missing/corrupt case) rather than
//  silently overwritten. Writers treat `save` failures as best-effort — a stale
//  checkpoint costs at most one lost mutation on resume, never the workout — so
//  the throw exists to let a caller log, not to abort the workout.
//
//  IDENTICAL COPY in both targets — `GymStreak/Data/Sync/` and
//  `GymStreakWatch Watch App/Managers/` — keep them in sync. Since audit item
//  P1.1 there IS a watch unit-test target (`GymStreakWatchTests`, see
//  `docs/watch-unit-tests.md`), so cover the watch copy there rather than relying
//  on the iOS twin — a schema drift between the copies compiles cleanly on both.
//

import Foundation

@MainActor
final class WatchActiveWorkoutCheckpointStore {
    nonisolated static let appGroupID = "group.com.gymstreak.shared"

    private let fileURL: URL?

    /// - Parameter directory: override for tests; defaults to the App Group's
    ///   `WorkoutSync` directory (shared with `WatchSyncStateStore`).
    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)?
            .appendingPathComponent("WorkoutSync", isDirectory: true)
        self.fileURL = base?.appendingPathComponent("active-workout-checkpoint.json")
        if let base { try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true) }
    }

    /// Loads the checkpoint, or nil when none exists. An undecodable file is
    /// quarantined (the missing/corrupt-checkpoint case) and reported as nil.
    func load() -> WatchActiveWorkoutCheckpoint? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        if let checkpoint = try? JSONDecoder().decode(WatchActiveWorkoutCheckpoint.self, from: data) {
            return checkpoint
        }
        try? FileManager.default.moveItem(at: fileURL, to: fileURL.appendingPathExtension("corrupt"))
        print("WatchActiveWorkoutCheckpointStore: checkpoint undecodable — quarantined as .corrupt")
        return nil
    }

    /// Atomically replaces the checkpoint. Throws on write failure so the caller
    /// knows the crash boundary did not advance.
    func save(_ checkpoint: WatchActiveWorkoutCheckpoint) throws {
        guard let fileURL else { throw CocoaError(.fileNoSuchFile) }
        let data = try JSONEncoder().encode(checkpoint)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Removes the checkpoint once finalization is durably past HealthKit (or on
    /// discard/reset). Best effort: a leftover file is reconciled to
    /// `.finalizationComplete`/`.none` on the next launch.
    func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    var hasCheckpoint: Bool {
        guard let fileURL else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}
