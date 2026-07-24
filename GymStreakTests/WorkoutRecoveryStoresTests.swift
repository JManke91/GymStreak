//
//  WorkoutRecoveryStoresTests.swift
//  GymStreakTests
//
//  The durable recovery ledger and anchor stores (ticket 09 of in-workout
//  routine editing): anchor archive round-trip and reset, fixed bootstrap
//  stability, idempotent discovery replay, duplicate-external-UUID conflict
//  accumulation, deletion→tombstone mapping, and cross-instance persistence.
//

import Foundation
import HealthKit
import Testing
@testable import GymStreak

@MainActor
struct WorkoutRecoveryStoresTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures
    private let base = Date(timeIntervalSince1970: 2_000_000)

    private func facts(
        externalUUID: UUID = UUID(),
        objectUUID: UUID = UUID()
    ) -> DiscoveredWorkoutFacts {
        DiscoveredWorkoutFacts(
            externalUUID: externalUUID,
            healthKitObjectUUID: objectUUID,
            startDate: base,
            endDate: base.addingTimeInterval(3600),
            activeEnergyKilocalories: 250,
            routineName: "Legs",
            routineId: UUID(),
            fromWatch: true
        )
    }

    // MARK: - Anchor store

    @Test
    func anchorRoundTripsAndResets() throws {
        let dir = try Fixtures.makeTempDirectory()
        let store = HealthKitWorkoutAnchorStore(directory: dir)

        #expect(store.loadAnchor() == nil)

        let anchor = HKQueryAnchor(fromValue: 77)
        try store.save(anchor: anchor)
        #expect(store.loadAnchor() == anchor)

        store.resetAnchor()
        #expect(store.loadAnchor() == nil)
    }

    @Test
    func bootstrapLowerBoundIsFixedAcrossCalls() throws {
        let dir = try Fixtures.makeTempDirectory()
        let store = HealthKitWorkoutAnchorStore(directory: dir)

        let first = store.bootstrapLowerBound(now: base)
        // A later "now" must NOT move the stored lower bound.
        let second = store.bootstrapLowerBound(now: base.addingTimeInterval(86_400 * 10))
        #expect(first == second)

        // Survives a reset of the anchor and a fresh store instance.
        store.resetAnchor()
        let reloaded = HealthKitWorkoutAnchorStore(directory: dir).bootstrapLowerBound(now: base.addingTimeInterval(99_999))
        #expect(reloaded == first)
    }

    // MARK: - Ledger store

    @Test
    func discoveryIsIdempotentOnReplay() throws {
        let dir = try Fixtures.makeTempDirectory()
        let store = WorkoutRecoveryLedgerStore(directory: dir)
        let f = facts()

        let a = try store.applyDiscovered(f, now: base)
        // Replay with a later "now": discoveredAt and identity must not move.
        let b = try store.applyDiscovered(f, now: base.addingTimeInterval(500))

        #expect(a == b)
        #expect(store.entries().count == 1)
        #expect(a.discoveredAt == base)
        #expect(a.hasExternalUUIDConflict == false)
    }

    @Test
    func secondObjectForSameExternalUUIDBecomesConflict() throws {
        let dir = try Fixtures.makeTempDirectory()
        let store = WorkoutRecoveryLedgerStore(directory: dir)
        let ext = UUID()

        try store.applyDiscovered(facts(externalUUID: ext, objectUUID: UUID()), now: base)
        let entry = try store.applyDiscovered(facts(externalUUID: ext, objectUUID: UUID()), now: base)

        #expect(entry.healthKitObjectUUIDs.count == 2)
        #expect(entry.hasExternalUUIDConflict)
        #expect(store.entries().count == 1)
    }

    @Test
    func deletionMapsObjectUUIDBackAndTombstonesWhenLast() throws {
        let dir = try Fixtures.makeTempDirectory()
        let store = WorkoutRecoveryLedgerStore(directory: dir)
        let ext = UUID(), obj = UUID()

        try store.applyDiscovered(facts(externalUUID: ext, objectUUID: obj), now: base)

        // Unknown UUID is a safe no-op.
        #expect(store.applyDeleted(objectUUID: UUID(), now: base) == nil)

        let tombstoned = store.applyDeleted(objectUUID: obj, now: base.addingTimeInterval(10))
        #expect(tombstoned?.state == .tombstoned)
        #expect(tombstoned?.deletedAt == base.addingTimeInterval(10))
        #expect(store.entry(forExternalUUID: ext)?.state == .tombstoned)
    }

    @Test
    func deletionOfOneConflictObjectKeepsCandidateAlive() throws {
        let dir = try Fixtures.makeTempDirectory()
        let store = WorkoutRecoveryLedgerStore(directory: dir)
        let ext = UUID(), objA = UUID(), objB = UUID()

        try store.applyDiscovered(facts(externalUUID: ext, objectUUID: objA), now: base)
        try store.applyDiscovered(facts(externalUUID: ext, objectUUID: objB), now: base)

        let after = store.applyDeleted(objectUUID: objA, now: base)
        #expect(after?.state != .tombstoned)
        #expect(after?.healthKitObjectUUIDs == [objB])
    }

    @Test
    func entriesPersistAcrossStoreInstances() throws {
        let dir = try Fixtures.makeTempDirectory()
        let ext = UUID()
        try WorkoutRecoveryLedgerStore(directory: dir).applyDiscovered(
            facts(externalUUID: ext), now: base
        )

        let reopened = WorkoutRecoveryLedgerStore(directory: dir)
        #expect(reopened.entry(forExternalUUID: ext) != nil)
    }

    @Test
    func upsertReplacesStateInPlace() throws {
        let dir = try Fixtures.makeTempDirectory()
        let store = WorkoutRecoveryLedgerStore(directory: dir)
        var entry = try store.applyDiscovered(facts(), now: base)

        entry.state = .placeholderSaved
        try store.upsert(entry)

        #expect(store.entry(forExternalUUID: entry.externalUUID)?.state == .placeholderSaved)
        #expect(store.entries().count == 1)
    }
}
