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
//  **Shape rule for anything added here.** A "must not seed" assertion drives
//  the stub to `finish()` and asserts on the recovery's *return value*; a
//  "seeds only after waiting" assertion asserts an elapsed-time **lower** bound.
//  Neither `Task.yield()` nor a bare count check proves anything: both are also
//  satisfied by a recovery that was merely still suspended, and two tests
//  written that way during an earlier attempt passed against both the broken
//  gate and the fixed one.
//

import Testing
import SwiftData
import Foundation
@testable import GymStreak

// `StubCloudSyncStatus` lives in Support/CloudSyncTestDoubles.swift — shared
// with RoutinePlanLinkRepairTests.

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

    /// Short enough to wait for in a test, long enough that a lower-bound
    /// assertion against it is not measuring scheduler noise.
    private static let settleWindow = Duration.milliseconds(200)
    /// Used where the point is that the *real* signal decided: a recovery that
    /// returns two orders of magnitude inside this window cannot have fallen
    /// back on the timer. Kept finite so that a gate which never fires ends the
    /// test in seconds instead of hanging the suite.
    private static let longSettleWindow = Duration.seconds(5)
    private static let importBurstGrace = Duration.milliseconds(50)

    private func makeSeeder(
        storedVersion: Int?,
        status: StubCloudSyncStatus,
        settleWindow: Duration = DefaultContentSeederRecoveryTests.settleWindow,
        importBurstGrace: Duration = DefaultContentSeederRecoveryTests.importBurstGrace
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
            cloudVersionStore: versionStore,
            settleWindow: settleWindow,
            importBurstGrace: importBurstGrace
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
            status: status,
            settleWindow: Self.longSettleWindow
        )

        let didSeed = await seeder.recoverStrandedLibraryIfNeeded()

        #expect(didSeed)
        #expect(try exerciseCount(context) == SeedExerciseCatalog.entries.count)
    }

    /// `.failing` is grouped with `.off` on purpose: a broken store or a rejected
    /// export means nothing is arriving, so an empty library must be re-seeded
    /// rather than waited on forever.
    @Test
    func recoversWhenSyncIsBroken() async throws {
        let status = StubCloudSyncStatus(
            initial: CloudSyncStatus(state: .failing, lastSuccessfulSync: nil)
        )
        let (context, seeder, _) = makeSeeder(
            storedVersion: SeedExerciseCatalog.currentVersion,
            status: status,
            settleWindow: Self.longSettleWindow
        )

        let didSeed = await seeder.recoverStrandedLibraryIfNeeded()

        #expect(didSeed)
        #expect(try exerciseCount(context) == SeedExerciseCatalog.entries.count)
    }

    /// The real signal, on the device it exists for: one that has **never**
    /// completed a transfer before this session, so `lastSuccessfulSync` is nil.
    /// The old gate read that nil as "still importing" and waited forever, which
    /// is the dead end the recovery was written to escape.
    @Test
    func recoversOnceAnImportCompletedAndTheStoreIsStillEmpty() async throws {
        let status = StubCloudSyncStatus()
        let (context, seeder, _) = makeSeeder(
            storedVersion: SeedExerciseCatalog.currentVersion,
            status: status,
            settleWindow: Self.longSettleWindow
        )

        let start = ContinuousClock.now
        let recovery = Task { await seeder.recoverStrandedLibraryIfNeeded() }
        await status.waitForSubscriber()
        status.emit(
            CloudSyncStatus(
                state: .upToDate,
                lastSuccessfulSync: nil,
                hasCompletedImportThisSession: true
            )
        )
        status.finish()
        let didSeed = await recovery.value
        let elapsed = ContinuousClock.now - start

        #expect(didSeed)
        #expect(try exerciseCount(context) == SeedExerciseCatalog.entries.count)
        // The import flag decided, not the timer — the settle window is 25×
        // longer than this took.
        #expect(elapsed < Self.longSettleWindow)
        // ...and the burst grace was still observed before acting on it.
        #expect(elapsed >= Self.importBurstGrace)
    }

    /// A new device of an existing user, mid-import — with `UserDefaults`
    /// timestamps that survived a previous install, so `lastSuccessfulSync` is
    /// already non-nil and the old gate seeded straight into the import window.
    /// The status is held at `.syncing` past the settle window: an in-flight
    /// transfer outranks the backstop.
    @Test
    func doesNotSeedWhileATransferIsInFlight() async throws {
        let status = StubCloudSyncStatus()
        let (context, seeder, _) = makeSeeder(
            storedVersion: SeedExerciseCatalog.currentVersion,
            status: status
        )

        let start = ContinuousClock.now
        let recovery = Task { await seeder.recoverStrandedLibraryIfNeeded() }
        await status.waitForSubscriber()
        status.emit(CloudSyncStatus(state: .syncing, lastSuccessfulSync: Date()))
        status.finish()

        let didSeed = await recovery.value
        let elapsed = ContinuousClock.now - start

        #expect(!didSeed)
        #expect(try exerciseCount(context) == 0)
        // Proves the window really did expire under `.syncing` and was ignored,
        // rather than the recovery simply returning before it opened.
        #expect(elapsed >= Self.settleWindow)
    }

    /// The backstop: a device where mirroring reports nothing at all. The status
    /// is the optimistic cold-launch `.upToDate` — no events opened yet — which
    /// is exactly the status a new device of an existing user shows on iteration
    /// one, so seeding on it directly would be a duplicate-catalog regression.
    /// The elapsed lower bound is what pins that it waited instead.
    @Test
    func recoversAfterTheSettleWindowWhenCloudKitNeverReports() async throws {
        let status = StubCloudSyncStatus(
            initial: CloudSyncStatus(state: .upToDate, lastSuccessfulSync: nil)
        )
        let (context, seeder, _) = makeSeeder(
            storedVersion: SeedExerciseCatalog.currentVersion,
            status: status
        )

        let start = ContinuousClock.now
        let recovery = Task { await seeder.recoverStrandedLibraryIfNeeded() }
        await status.waitForSubscriber()
        // Ending the status stream leaves the settle timer as the only source
        // still open, so a gate that ignores it returns `false` in milliseconds
        // instead of hanging the suite.
        status.finish()

        let didSeed = await recovery.value
        let elapsed = ContinuousClock.now - start

        #expect(didSeed)
        #expect(try exerciseCount(context) == SeedExerciseCatalog.entries.count)
        #expect(elapsed >= Self.settleWindow)
    }

    /// Offline, where `makeState()` pins `.waiting` and quiescence never comes.
    /// Recovered on the same backstop and for the same reason: an over-eager
    /// seed is collapsed by the next launch's dedup pass, an empty library is
    /// not recoverable from inside the app.
    @Test
    func recoversAnOfflineStrandedDeviceAfterTheSettleWindow() async throws {
        let status = StubCloudSyncStatus(
            initial: CloudSyncStatus(state: .waiting, lastSuccessfulSync: nil)
        )
        let (context, seeder, _) = makeSeeder(
            storedVersion: SeedExerciseCatalog.currentVersion,
            status: status
        )

        let start = ContinuousClock.now
        let recovery = Task { await seeder.recoverStrandedLibraryIfNeeded() }
        await status.waitForSubscriber()
        // Ending the status stream leaves the settle timer as the only source
        // still open, so a gate that ignores it returns `false` in milliseconds
        // instead of hanging the suite.
        status.finish()

        let didSeed = await recovery.value
        let elapsed = ContinuousClock.now - start

        #expect(didSeed)
        #expect(try exerciseCount(context) == SeedExerciseCatalog.entries.count)
        #expect(elapsed >= Self.settleWindow)
    }

    /// The one way the real signal can lie: import events arrive in bursts, and
    /// an early batch can report success before a later one delivers anything.
    /// The grace is what catches it — the recovery re-reads the store after
    /// waiting rather than acting on the event that woke it. The surviving
    /// `lastSuccessfulSync` is what the old gate seeded on outright.
    @Test
    func doesNotSeedWhenAnImportBurstDeliversDuringTheGrace() async throws {
        let status = StubCloudSyncStatus()
        let grace = Duration.milliseconds(400)
        let (context, seeder, _) = makeSeeder(
            storedVersion: SeedExerciseCatalog.currentVersion,
            status: status,
            settleWindow: Self.longSettleWindow,
            importBurstGrace: grace
        )

        let recovery = Task { await seeder.recoverStrandedLibraryIfNeeded() }
        await status.waitForSubscriber()
        status.emit(
            CloudSyncStatus(
                state: .upToDate,
                lastSuccessfulSync: Date(),
                hasCompletedImportThisSession: true
            )
        )
        // Well inside the grace: the recovery has read the store as empty and is
        // waiting before it acts.
        try await Task.sleep(for: .milliseconds(100))
        context.insert(Exercise(name: "Bench Press", muscleGroups: ["Chest"]))
        try context.save()
        status.finish()

        let didSeed = await recovery.value

        #expect(!didSeed)
        #expect(try exerciseCount(context) == 1)
    }

    @Test
    func leavesAStoreThatHoldsUserContentAlone() async throws {
        let status = StubCloudSyncStatus(initial: .off)
        let (context, seeder, _) = makeSeeder(
            storedVersion: SeedExerciseCatalog.currentVersion,
            status: status,
            settleWindow: Self.longSettleWindow
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
        let (context, seeder, _) = makeSeeder(
            storedVersion: nil,
            status: status,
            settleWindow: Self.longSettleWindow
        )

        let didSeed = await seeder.recoverStrandedLibraryIfNeeded()

        #expect(!didSeed)
        #expect(try exerciseCount(context) == 0)

        seeder.run()
        #expect(try exerciseCount(context) == SeedExerciseCatalog.entries.count)
    }
}
