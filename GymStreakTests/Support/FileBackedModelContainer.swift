//
//  FileBackedModelContainer.swift
//  GymStreakTests
//
//  A disposable ON-DISK SwiftData container over the full app schema.
//
//  Use it instead of `InMemoryModelContainer` whenever the behavior under test
//  depends on the store itself: an in-memory store performs no row-version
//  conflict resolution between sibling contexts, so a change that one context
//  silently loses on device passes every in-memory test. That is exactly how the
//  2026-08-11 rest-not-persisting bug reached a device (see
//  `docs/watch-sync.md`, "The main-context mirror is load-bearing").
//

import Foundation
import SwiftData
@testable import GymStreak

enum FileBackedModelContainer {
    /// Returns the container plus a cleanup closure that removes the store and
    /// its `-wal`/`-shm` siblings.
    @MainActor
    static func make() throws -> (container: ModelContainer, cleanUp: () -> Void) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gymstreak-tests-\(UUID().uuidString).store")
        // `GymStreakSchema.modelTypes` is the single source of truth for the
        // app's schema — never a hand-rolled list, which silently drifts.
        let schema = Schema(GymStreakSchema.modelTypes)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)]
        )
        return (container, {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: url.deletingLastPathComponent()
                        .appendingPathComponent(url.lastPathComponent + suffix)
                )
            }
        })
    }
}
