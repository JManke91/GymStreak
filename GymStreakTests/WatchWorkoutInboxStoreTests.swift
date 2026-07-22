//
//  WatchWorkoutInboxStoreTests.swift
//  GymStreakTests
//
//  Covers the iOS durable receive inbox and the terminal receipt store
//  (ticket 04): legacy UserDefaults migration order, duplicate-delivery
//  dedupe, malformed-payload quarantine, observable write failures, receipt
//  round-trips, and the recorded performance budget for large synthetic
//  receipt histories.
//

import Foundation
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct WatchWorkoutInboxStoreTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures

    private func store(_ workout: CompletedWatchWorkout, into inbox: WatchWorkoutInboxStore) throws {
        try inbox.store(payloadData: try JSONEncoder().encode(workout), workoutId: workout.id)
    }

    // MARK: - Inbox

    @Test
    func legacyMigrationPreservesOrderAndClearsBlob() throws {
        let dir = try Fixtures.makeTempDirectory()
        let (defaults, suiteName) = Fixtures.makeDefaultsSuite()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacy = [Fixtures.makeWorkout(), Fixtures.makeWorkout(), Fixtures.makeWorkout()]
        defaults.set(try JSONEncoder().encode(legacy), forKey: WatchWorkoutInboxStore.legacyDefaultsKey)

        let inbox = WatchWorkoutInboxStore(directory: dir, legacyDefaults: defaults)

        #expect(inbox.entries().compactMap(\.completedWorkout).map(\.id) == legacy.map(\.id))
        #expect(defaults.data(forKey: WatchWorkoutInboxStore.legacyDefaultsKey) == nil)

        // Migrated entries stay ahead of a live arrival.
        let live = Fixtures.makeWorkout()
        try store(live, into: inbox)
        #expect(inbox.entries().compactMap(\.completedWorkout).map(\.id) == legacy.map(\.id) + [live.id])
    }

    @Test
    func duplicateDeliveryKeepsSingleEntryAtOriginalPosition() throws {
        let dir = try Fixtures.makeTempDirectory()
        let inbox = WatchWorkoutInboxStore(directory: dir, legacyDefaults: nil)
        let first = Fixtures.makeWorkout()
        let second = Fixtures.makeWorkout()

        // Fast-path (sendMessage) and background (transferUserInfo) deliveries
        // of the same workout produce exactly one inbox entry.
        try store(first, into: inbox)
        try store(second, into: inbox)
        try store(first, into: inbox)

        #expect(inbox.entries().compactMap(\.completedWorkout).map(\.id) == [first.id, second.id])
    }

    @Test
    func malformedPayloadIsQuarantinedAndOthersStillDecode() throws {
        let dir = try Fixtures.makeTempDirectory()
        let inbox = WatchWorkoutInboxStore(directory: dir, legacyDefaults: nil)
        let valid = Fixtures.makeWorkout()
        try store(valid, into: inbox)
        try inbox.store(payloadData: Data("garbage".utf8), workoutId: UUID())

        let entries = inbox.entries()

        #expect(entries.compactMap(\.completedWorkout).map(\.id) == [valid.id])
        let quarantined = (try? FileManager.default.contentsOfDirectory(
            at: dir.appendingPathComponent("Quarantine"), includingPropertiesForKeys: nil)) ?? []
        #expect(quarantined.count == 1)
        // Quarantined deliveries are never replayed.
        #expect(inbox.entries().compactMap(\.completedWorkout).map(\.id) == [valid.id])
    }

    @Test
    func storeWriteFailureThrowsAndPersistsNothing() throws {
        let dir = try Fixtures.makeTempDirectory()
        let inbox = WatchWorkoutInboxStore(directory: dir, legacyDefaults: nil)
        let restore = try Fixtures.makeReadOnly(dir.appendingPathComponent("Inbox"))
        defer { restore() }

        #expect(throws: Error.self) {
            try store(Fixtures.makeWorkout(), into: inbox)
        }
        #expect(inbox.entries().isEmpty)
    }

    @Test
    func removeRetiresEntry() throws {
        let dir = try Fixtures.makeTempDirectory()
        let inbox = WatchWorkoutInboxStore(directory: dir, legacyDefaults: nil)
        let workout = Fixtures.makeWorkout()
        try store(workout, into: inbox)

        let entry = try #require(inbox.entries().first)
        inbox.remove(entry)

        #expect(inbox.entries().isEmpty)
        #expect(!inbox.containsEntry(for: workout.id))
    }

    // MARK: - Receipts

    @Test
    func receiptRoundTripsAndSurvivesReload() throws {
        let dir = try Fixtures.makeTempDirectory()
        let receipts = WorkoutIngestReceiptStore(directory: dir)
        let receipt = WorkoutIngestReceipt(
            workoutId: UUID(),
            healthKitWorkoutId: UUID(),
            phase: .readyToAcknowledgeNotRequested,
            recordedAt: Date(timeIntervalSince1970: 1_700_000_700)
        )

        try receipts.record(receipt)

        #expect(receipts.receipt(for: receipt.workoutId!) == receipt)
        #expect(receipts.receipt(for: UUID()) == nil)
        // A fresh store over the same directory (relaunch) still answers.
        #expect(WorkoutIngestReceiptStore(directory: dir).receipt(for: receipt.workoutId!) == receipt)
    }

    @Test
    func receiptWriteFailureThrows() throws {
        let dir = try Fixtures.makeTempDirectory()
        let receipts = WorkoutIngestReceiptStore(directory: dir)
        let restore = try Fixtures.makeReadOnly(dir)
        defer { restore() }

        #expect(throws: Error.self) {
            try receipts.record(WorkoutIngestReceipt(
                workoutId: UUID(), healthKitWorkoutId: nil,
                phase: .readyToAcknowledgeNotRequested, recordedAt: Date()
            ))
        }
    }

    @Test
    func templateReceiptNeedsNoWorkoutCorrelation() throws {
        let dir = try Fixtures.makeTempDirectory()
        let receipts = WorkoutIngestReceiptStore(directory: dir)
        let key = TemplateTransactionKey(senderEpoch: UUID(), routineID: UUID(), sequence: 4)
        let receipt = WorkoutIngestReceipt(
            workoutId: nil,
            healthKitWorkoutId: nil,
            phase: .readyToAcknowledge,
            recordedAt: Date(),
            transactionID: UUID(),
            senderEpoch: key.senderEpoch,
            routineID: key.routineID,
            sequence: key.sequence,
            outcomeRaw: TemplateTransactionOutcome.applied.rawValue,
            protocolVersion: WatchRoutineSync.templateUpdateVersion,
            routineEpoch: UUID(),
            routineGeneration: 7
        )

        try receipts.record(receipt)

        #expect(receipts.receipt(for: key) == receipt)
        #expect(receipts.readyTemplateReceipts() == [receipt])
    }

    /// Recorded performance budget for indefinite receipt retention: the
    /// per-workout-file representation must keep record and lookup O(1) —
    /// 1000 records plus 1000 lookups well under the budget, with no
    /// monolithic rewrite growing per receipt. Budgets are deliberately
    /// generous to avoid CI flakiness; see docs/watch-sync.md for baselines.
    @Test
    func largeSyntheticReceiptHistoryStaysWithinPerformanceBudget() throws {
        let dir = try Fixtures.makeTempDirectory()
        let receipts = WorkoutIngestReceiptStore(directory: dir)
        let ids = (0..<1000).map { _ in UUID() }

        let writeStart = Date()
        for id in ids {
            try receipts.record(WorkoutIngestReceipt(
                workoutId: id, healthKitWorkoutId: UUID(),
                phase: .readyToAcknowledgeNotRequested, recordedAt: Date()
            ))
        }
        let writeElapsed = Date().timeIntervalSince(writeStart)

        let lookupStart = Date()
        for id in ids {
            #expect(receipts.receipt(for: id) != nil)
        }
        let lookupElapsed = Date().timeIntervalSince(lookupStart)

        #expect(writeElapsed < 10, "1000 receipt writes took \(writeElapsed)s (budget 10s)")
        #expect(lookupElapsed < 5, "1000 receipt lookups took \(lookupElapsed)s (budget 5s)")
    }
}
