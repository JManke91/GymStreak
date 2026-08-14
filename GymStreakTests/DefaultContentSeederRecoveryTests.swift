//
//  DefaultContentSeederRecoveryTests.swift
//  GymStreakTests
//
//  Covers the stranded-library recovery: the catalog version flag lives in
//  iCloud key-value storage while the seeded exercises live in CloudKit, so a
//  device can carry "already seeded v2" over a store that holds nothing. These
//  tests pin when the recovery re-seeds and — more importantly — when it must
//  keep its hands off.
//
//  The stored version reads `max(iCloud KV, defaults)`. Both halves are injected
//  here — the real KV store is a single process-wide instance whose contents
//  outlive the app, so a test must never touch it.
//

import Testing
import SwiftData
import Foundation
@testable import GymStreak

/// Feeds the seeder a scripted sync status; `emit` drives the recovery's wait.
@MainActor
private final class StubCloudSyncStatus: CloudSyncStatusProviding {
    private(set) var currentStatus: CloudSyncStatus = CloudSyncStatus(
        state: .syncing,
        lastSuccessfulSync: nil
    )
    private var continuations: [UUID: AsyncStream<CloudSyncStatus>.Continuation] = [:]

    init(initial: CloudSyncStatus = CloudSyncStatus(state: .syncing, lastSuccessfulSync: nil)) {
        self.currentStatus = initial
    }

    func statusUpdates() -> AsyncStream<CloudSyncStatus> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(currentStatus)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations[id] = nil }
            }
        }
    }

    func emit(_ status: CloudSyncStatus) {
        currentStatus = status
        for continuation in continuations.values {
            continuation.yield(status)
        }
    }
}

/// Stands in for iCloud key-value storage, which must never be touched by tests.
private final class InMemoryVersionStore: SeedCatalogVersionStore, @unchecked Sendable {
    // `@unchecked` with a lock: the protocol is `Sendable` because production
    // reads it from any isolation, while a test needs to seed and inspect it.
    private let lock = NSLock()
    private var versions: [String: Int]

    init(_ versions: [String: Int] = [:]) {
        self.versions = versions
    }

    func version(forKey key: String) -> Int {
        lock.withLock { versions[key] ?? 0 }
    }

    func setVersion(_ version: Int, forKey key: String) {
        lock.withLock { versions[key] = version }
    }
}

// Serialized for the same reason as the other SwiftData suites: concurrent
// in-memory container creation is not safe within one process.
@Suite(.serialized)
@MainActor
struct DefaultContentSeederRecoveryTests {

    private func makeSeeder(
        storedVersion: Int?,
        status: StubCloudSyncStatus
    ) -> (context: ModelContext, seeder: DefaultContentSeeder, versionStore: InMemoryVersionStore) {
        let container = InMemoryModelContainer.make()
        let context = ModelContext(container)
        let suiteName = "DefaultContentSeederRecoveryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let versionStore = InMemoryVersionStore()
        if let storedVersion {
            versionStore.setVersion(storedVersion, forKey: "seedCatalogVersion")
        }
        let seeder = DefaultContentSeeder(
            modelContext: context,
            cloudSyncStatus: status,
            defaults: defaults,
            cloudVersionStore: versionStore
        )
        return (context, seeder, versionStore)
    }

    private func exerciseCount(_ context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<Exercise>())
    }

    @Test
    func recoversWhenCloudKitCanNeverDeliver() async throws {
        let status = StubCloudSyncStatus(initial: .off)
        let (context, seeder, _) = makeSeeder(
            storedVersion: SeedExerciseCatalog.currentVersion,
            status: status
        )

        let didSeed = await seeder.recoverStrandedLibraryIfNeeded()

        #expect(didSeed)
        #expect(try exerciseCount(context) == SeedExerciseCatalog.entries.count)
    }

    @Test
    func recoversOnceASyncCompletedAndTheStoreIsStillEmpty() async throws {
        let status = StubCloudSyncStatus()
        let (context, seeder, _) = makeSeeder(
            storedVersion: SeedExerciseCatalog.currentVersion,
            status: status
        )

        let recovery = Task { await seeder.recoverStrandedLibraryIfNeeded() }
        await Task.yield()
        // Still importing: nothing may be written yet.
        #expect(try exerciseCount(context) == 0)

        status.emit(CloudSyncStatus(state: .upToDate, lastSuccessfulSync: Date()))

        #expect(await recovery.value)
        #expect(try exerciseCount(context) == SeedExerciseCatalog.entries.count)
    }

    @Test
    func waitsWhileCloudKitHasNotFinishedAnyTransfer() async throws {
        let status = StubCloudSyncStatus()
        let (context, seeder, _) = makeSeeder(
            storedVersion: SeedExerciseCatalog.currentVersion,
            status: status
        )

        let recovery = Task { await seeder.recoverStrandedLibraryIfNeeded() }
        await Task.yield()
        status.emit(CloudSyncStatus(state: .syncing, lastSuccessfulSync: nil))
        await Task.yield()

        // A new device of an existing user looks exactly like this mid-import;
        // seeding here would upload a duplicate catalog.
        #expect(try exerciseCount(context) == 0)
        recovery.cancel()
    }

    @Test
    func leavesAStoreThatHoldsUserContentAlone() async throws {
        let status = StubCloudSyncStatus(initial: .off)
        let (context, seeder, _) = makeSeeder(
            storedVersion: SeedExerciseCatalog.currentVersion,
            status: status
        )
        // The user deleted the built-ins but kept an exercise of their own —
        // this is a deliberate library, not a stranded one.
        context.insert(Exercise(name: "Bench Press", muscleGroups: ["Chest"]))
        try context.save()

        let didSeed = await seeder.recoverStrandedLibraryIfNeeded()

        #expect(!didSeed)
        #expect(try exerciseCount(context) == 1)
    }

    @Test
    func doesNothingWhenTheNormalSeedPassCanStillRun() async throws {
        let status = StubCloudSyncStatus(initial: .off)
        // No stored version at all: `run()` owns this case.
        let (context, seeder, _) = makeSeeder(storedVersion: nil, status: status)

        let didSeed = await seeder.recoverStrandedLibraryIfNeeded()

        #expect(!didSeed)
        #expect(try exerciseCount(context) == 0)

        seeder.run()
        #expect(try exerciseCount(context) == SeedExerciseCatalog.entries.count)
    }
}
