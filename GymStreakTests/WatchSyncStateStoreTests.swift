//
//  WatchSyncStateStoreTests.swift
//  GymStreakTests
//
//  Covers the watch-side durable outgoing queue (ticket 04): legacy
//  UserDefaults migration order, idempotent FIFO enqueue, persisted phase
//  advancement, observable atomic-write failure, ack retirement, quarantine,
//  corrupt-state handling, and the recorded performance budget for large
//  synthetic queues. The queue file is an identical copy in both targets, so
//  these tests stand in for the missing watch unit-test target.
//

import Foundation
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct WatchSyncStateStoreTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures

    @Test
    func legacyMigrationPreservesOrderAndClearsBlob() throws {
        let dir = try Fixtures.makeTempDirectory()
        let (defaults, suiteName) = Fixtures.makeDefaultsSuite()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacy = [Fixtures.makeWorkout(), Fixtures.makeWorkout(), Fixtures.makeWorkout()]
        defaults.set(try JSONEncoder().encode(legacy), forKey: WatchSyncStateStore.legacyDefaultsKey)

        let queue = WatchSyncStateStore(directory: dir, legacyDefaults: defaults)

        #expect(queue.all.compactMap(\.completedWorkout).map(\.id) == legacy.map(\.id))
        #expect(queue.all.allSatisfy { $0.phase == .transportEligible })
        #expect(defaults.data(forKey: WatchSyncStateStore.legacyDefaultsKey) == nil)

        // Migrated state must survive a relaunch from the state file alone.
        let reloaded = WatchSyncStateStore(directory: dir, legacyDefaults: defaults)
        #expect(reloaded.all.compactMap(\.completedWorkout).map(\.id) == legacy.map(\.id))
    }

    @Test
    func completedMigrationDoesNotReopenLegacyDefaults() throws {
        let dir = try Fixtures.makeTempDirectory()
        let (defaults, suiteName) = Fixtures.makeDefaultsSuite()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let migratedWorkout = Fixtures.makeWorkout()
        defaults.set(
            try JSONEncoder().encode([migratedWorkout]),
            forKey: WatchSyncStateStore.legacyDefaultsKey
        )
        _ = WatchSyncStateStore(directory: dir, legacyDefaults: defaults)

        // A stale legacy blob must never be consulted after the one-time
        // migration marker commits. This also avoids reopening the App Group
        // preferences suite on every watch startup.
        let staleWorkout = Fixtures.makeWorkout()
        defaults.set(
            try JSONEncoder().encode([staleWorkout]),
            forKey: WatchSyncStateStore.legacyDefaultsKey
        )

        let reloaded = WatchSyncStateStore(directory: dir, legacyDefaults: defaults)

        #expect(reloaded.all.compactMap(\.completedWorkout).map(\.id) == [migratedWorkout.id])
    }

    @Test
    func malformedLegacyDataRetriesAfterItBecomesDecodable() throws {
        let dir = try Fixtures.makeTempDirectory()
        let (defaults, suiteName) = Fixtures.makeDefaultsSuite()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(Data("malformed workout queue".utf8), forKey: WatchSyncStateStore.legacyDefaultsKey)
        defaults.set(Data("malformed routine cache".utf8), forKey: WatchSyncStateStore.legacyRoutinesKey)

        let firstAttempt = WatchSyncStateStore(directory: dir, legacyDefaults: defaults)
        #expect(firstAttempt.all.isEmpty)
        #expect(firstAttempt.effectiveRoutines().isEmpty)

        let workout = Fixtures.makeWorkout()
        let routine = Fixtures.makeWatchRoutine(name: "Recovered")
        defaults.set(
            try JSONEncoder().encode([workout]),
            forKey: WatchSyncStateStore.legacyDefaultsKey
        )
        defaults.set(
            try JSONEncoder().encode([routine]),
            forKey: WatchSyncStateStore.legacyRoutinesKey
        )

        let recovered = WatchSyncStateStore(directory: dir, legacyDefaults: defaults)

        #expect(recovered.all.compactMap(\.completedWorkout).map(\.id) == [workout.id])
        #expect(recovered.effectiveRoutines().map(\.id) == [routine.id])
    }

    @Test
    func enqueueIsIdempotentAndPreservesFIFOPositionAndFrozenBytes() throws {
        let dir = try Fixtures.makeTempDirectory()
        let queue = WatchSyncStateStore(directory: dir, legacyDefaults: nil)

        let first = Fixtures.makeWorkout(routineName: "Original")
        let second = Fixtures.makeWorkout()
        try queue.enqueue(first, phase: .awaitingHealthKitMetadata)
        try queue.enqueue(second, phase: .transportEligible)

        // Re-enqueueing the same workout id with different content must keep
        // the original frozen bytes, phase, and FIFO position.
        let mutated = Fixtures.makeWorkout(id: first.id, routineName: "Mutated", endTime: Date())
        let entry = try queue.enqueue(mutated, phase: .transportEligible)

        #expect(queue.all.count == 2)
        #expect(queue.all.first?.completedWorkout?.id == first.id)
        #expect(entry.completedWorkout?.routineName == "Original")
        #expect(entry.phase == .awaitingHealthKitMetadata)
    }

    @Test
    func advancePersistsPhaseAcrossRelaunch() throws {
        let dir = try Fixtures.makeTempDirectory()
        let queue = WatchSyncStateStore(directory: dir, legacyDefaults: nil)
        let workout = Fixtures.makeWorkout()
        try queue.enqueue(workout, phase: .awaitingHealthKitMetadata)

        try queue.advance(id: workout.id, to: .awaitingHealthKitFinish)
        try queue.advance(id: workout.id, to: .transportEligible)

        let reloaded = WatchSyncStateStore(directory: dir, legacyDefaults: nil)
        #expect(reloaded.entry(id: workout.id)?.phase == .transportEligible)
        #expect(reloaded.transportEligibleEntries().count == 1)
    }

    @Test
    func atomicWriteFailureThrowsAndEnqueuesNothing() throws {
        let dir = try Fixtures.makeTempDirectory()
        let queue = WatchSyncStateStore(directory: dir, legacyDefaults: nil)
        let restore = try Fixtures.makeReadOnly(dir)
        defer { restore() }

        #expect(throws: Error.self) {
            try queue.enqueue(Fixtures.makeWorkout(), phase: .awaitingHealthKitMetadata)
        }
        #expect(queue.all.isEmpty)

        restore()
        let reloaded = WatchSyncStateStore(directory: dir, legacyDefaults: nil)
        #expect(reloaded.all.isEmpty)
    }

    @Test
    func advanceWriteFailureKeepsPreviousPhase() throws {
        let dir = try Fixtures.makeTempDirectory()
        let queue = WatchSyncStateStore(directory: dir, legacyDefaults: nil)
        let workout = Fixtures.makeWorkout()
        try queue.enqueue(workout, phase: .awaitingHealthKitMetadata)

        let restore = try Fixtures.makeReadOnly(dir)
        defer { restore() }

        #expect(throws: Error.self) {
            try queue.advance(id: workout.id, to: .transportEligible)
        }
        #expect(queue.entry(id: workout.id)?.phase == .awaitingHealthKitMetadata)
        #expect(queue.transportEligibleEntries().isEmpty)
    }

    @Test
    func retireRemovesEntryAndQuarantineExcludesFromTransport() throws {
        let dir = try Fixtures.makeTempDirectory()
        let queue = WatchSyncStateStore(directory: dir, legacyDefaults: nil)
        let acked = Fixtures.makeWorkout()
        let poisoned = Fixtures.makeWorkout()
        try queue.enqueue(acked, phase: .transportEligible)
        try queue.enqueue(poisoned, phase: .transportEligible)

        queue.retire(id: acked.id)
        queue.quarantine(id: poisoned.id, reason: "payloadTooLarge")

        #expect(queue.entry(id: acked.id) == nil)
        #expect(queue.entry(id: poisoned.id)?.phase == .quarantined)
        #expect(queue.entry(id: poisoned.id)?.quarantineReason == "payloadTooLarge")
        #expect(queue.transportEligibleEntries().isEmpty)
    }

    /// Launch-time recovery: entries a previous process left mid-HealthKit-
    /// finalization become transport-eligible (the payload must still reach
    /// iOS); quarantined and already-eligible entries are untouched, and the
    /// promotion is persisted.
    @Test
    func promoteInterruptedFinalizationsPromotesOnlyHealthKitPhases() throws {
        let dir = try Fixtures.makeTempDirectory()
        let queue = WatchSyncStateStore(directory: dir, legacyDefaults: nil)
        let awaitingMetadata = Fixtures.makeWorkout()
        let awaitingFinish = Fixtures.makeWorkout()
        let eligible = Fixtures.makeWorkout()
        let poisoned = Fixtures.makeWorkout()
        try queue.enqueue(awaitingMetadata, phase: .awaitingHealthKitMetadata)
        try queue.enqueue(awaitingFinish, phase: .awaitingHealthKitFinish)
        try queue.enqueue(eligible, phase: .transportEligible)
        try queue.enqueue(poisoned, phase: .transportEligible)
        queue.quarantine(id: poisoned.id, reason: "payloadTooLarge")

        queue.promoteInterruptedFinalizations()

        #expect(queue.entry(id: awaitingMetadata.id)?.phase == .transportEligible)
        #expect(queue.entry(id: awaitingFinish.id)?.phase == .transportEligible)
        #expect(queue.entry(id: poisoned.id)?.phase == .quarantined)
        #expect(queue.transportEligibleEntries().count == 3)

        let reloaded = WatchSyncStateStore(directory: dir, legacyDefaults: nil)
        #expect(reloaded.transportEligibleEntries().count == 3)
    }

    @Test
    func corruptStateFileIsQuarantinedNotFatal() throws {
        let dir = try Fixtures.makeTempDirectory()
        let stateURL = dir.appendingPathComponent("outgoing-queue.json")
        try Data("not json".utf8).write(to: stateURL)

        let queue = WatchSyncStateStore(directory: dir, legacyDefaults: nil)
        #expect(queue.all.isEmpty)
        #expect(FileManager.default.fileExists(atPath: stateURL.appendingPathExtension("corrupt").path))

        // The queue stays fully usable afterwards.
        try queue.enqueue(Fixtures.makeWorkout(), phase: .transportEligible)
        #expect(queue.all.count == 1)
    }

    /// Recorded performance budget: 150 enqueues + phase advances against a
    /// growing state file (every mutation rewrites it atomically) must stay
    /// comfortably interactive. Budget is deliberately generous to avoid CI
    /// flakiness; see docs/watch-sync.md for the recorded baseline.
    @Test
    func largeSyntheticQueueStaysWithinPerformanceBudget() throws {
        let dir = try Fixtures.makeTempDirectory()
        let queue = WatchSyncStateStore(directory: dir, legacyDefaults: nil)
        let sets = (0..<12).map { Fixtures.makeSet(order: $0) }
        let exercise = Fixtures.makeExercise(sets: sets)

        let start = Date()
        for _ in 0..<150 {
            let workout = Fixtures.makeWorkout(exercises: [exercise])
            try queue.enqueue(workout, phase: .awaitingHealthKitMetadata)
            try queue.advance(id: workout.id, to: .transportEligible)
        }
        let elapsed = Date().timeIntervalSince(start)

        #expect(queue.transportEligibleEntries().count == 150)
        #expect(elapsed < 10, "150 enqueue+advance cycles took \(elapsed)s (budget 10s)")
    }
}
