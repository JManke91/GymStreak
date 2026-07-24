//
//  HealthKitWorkoutAnchorStore.swift
//  GymStreak
//
//  Durable persistence for the incremental HealthKit workout discovery anchor
//  (ticket 09 of in-workout routine editing). Replaces the old moving 30-day
//  full-store poll: an `HKAnchoredObjectQueryDescriptor` remembers everything
//  it has already seen for a FIXED predicate, and its opaque `HKQueryAnchor`
//  is persisted here so discovery is incremental across observer wake-ups and
//  relaunches.
//
//  Two pieces of state:
//    • the archived `HKQueryAnchor` (NSSecureCoding), and
//    • a single FIXED bootstrap lower-bound date, established once and reused
//      for the life of the anchor. The anchor and predicate are not
//      independently versioned, so the predicate MUST stay stable — pairing a
//      persisted anchor with a moving `now - 30 days` window is a bug (a diff
//      computed against a shifted window is undefined). See docs/watch-sync.md.
//
//  The anchor is committed only AFTER the ledger changes it produced commit,
//  so a crash between drain and persist replays the same changes idempotently
//  rather than skipping them (`WorkoutRecoveryCoordinator`).
//

import Foundation
import HealthKit

@MainActor
final class HealthKitWorkoutAnchorStore {
    private let anchorURL: URL?
    private let bootstrapURL: URL?

    /// How far back the FIRST-EVER bootstrap looks. A migrated install starts
    /// discovery 30 days before it first ran this pipeline; the value is then
    /// frozen so the anchor's predicate never shifts.
    static let bootstrapLookbackDays = 30

    /// - Parameter directory: override for tests; defaults to the App Group's
    ///   HealthKitRecovery directory.
    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WatchWorkoutInboxStore.appGroupID)?
            .appendingPathComponent("HealthKitRecovery", isDirectory: true)
        if let base {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        self.anchorURL = base?.appendingPathComponent("anchor.archive")
        self.bootstrapURL = base?.appendingPathComponent("bootstrap.json")
    }

    // MARK: - Anchor

    /// The persisted anchor, or nil to bootstrap a full first-run discovery. A
    /// corrupt/unreadable archive is treated as nil (rebuild through the same
    /// idempotent path).
    func loadAnchor() -> HKQueryAnchor? {
        guard let anchorURL, let data = try? Data(contentsOf: anchorURL) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    /// Atomically persists the anchor. Throws on failure so the caller keeps
    /// the prior anchor and replays the same changes next time.
    func save(anchor: HKQueryAnchor) throws {
        guard let anchorURL else { throw CocoaError(.fileNoSuchFile) }
        let data = try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
        try data.write(to: anchorURL, options: .atomic)
    }

    /// Discards the anchor (corrupt-anchor rebuild). The next drain bootstraps
    /// from the fixed lower-bound and re-applies every candidate idempotently.
    /// The bootstrap date is deliberately kept stable across resets.
    func resetAnchor() {
        guard let anchorURL else { return }
        try? FileManager.default.removeItem(at: anchorURL)
    }

    // MARK: - Bootstrap lower bound

    /// The FIXED lower-bound date for the discovery predicate. Established once
    /// (30 days before first run) and reused thereafter so the anchor's
    /// predicate never shifts. `now` is injectable for tests.
    func bootstrapLowerBound(now: Date = Date()) -> Date {
        if let bootstrapURL,
           let data = try? Data(contentsOf: bootstrapURL),
           let stored = try? JSONDecoder().decode(Date.self, from: data) {
            return stored
        }
        let lowerBound = Calendar.current.date(
            byAdding: .day, value: -Self.bootstrapLookbackDays, to: now
        ) ?? now
        if let bootstrapURL, let data = try? JSONEncoder().encode(lowerBound) {
            try? data.write(to: bootstrapURL, options: .atomic)
        }
        return lowerBound
    }
}
