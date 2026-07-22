//
//  WatchWorkoutFinalizerTests.swift
//  GymStreakTests
//
//  Covers the terminal finalization state machine (ticket 04): durable
//  freeze before HealthKit, required-metadata and finish failures preserving
//  the frozen payload/external UUID, no transport before successful
//  finalization, duplicate End convergence, and queue-write failure aborting
//  with no external side effect.
//

import Foundation
import Testing
@testable import GymStreak

@MainActor
private final class FakeFinalizationHealthKit: WorkoutFinalizationHealthKit {
    var metadataError: Error?
    var finishError: Error?
    private(set) var metadataCalls: [UUID] = []
    private(set) var finishCalls = 0

    func endCollectionAndAddMetadata(externalId: UUID) async throws {
        metadataCalls.append(externalId)
        if let metadataError { throw metadataError }
    }

    func finishWorkout() async throws {
        finishCalls += 1
        if let finishError { throw finishError }
    }
}

@Suite(.serialized)
@MainActor
struct WatchWorkoutFinalizerTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures

    private struct Harness {
        let queue: WatchSyncStateStore
        let finalizer: WatchWorkoutFinalizer
        let healthKit: FakeFinalizationHealthKit
    }

    private func makeHarness(directory: URL) -> Harness {
        let queue = WatchSyncStateStore(directory: directory, legacyDefaults: nil)
        return Harness(
            queue: queue,
            finalizer: WatchWorkoutFinalizer(syncState: queue),
            healthKit: FakeFinalizationHealthKit()
        )
    }

    @Test
    func happyPathRunsOneFinalizationSequenceAndTransports() async throws {
        let harness = makeHarness(directory: try Fixtures.makeTempDirectory())
        let workout = Fixtures.makeWorkout()
        var transports = 0

        let outcome = await harness.finalizer.finalize(workout, healthKit: harness.healthKit) { transports += 1 }

        guard case .completed = outcome else {
            Issue.record("expected .completed, got \(outcome)")
            return
        }
        #expect(harness.queue.entry(id: workout.id)?.phase == .transportEligible)
        #expect(harness.healthKit.metadataCalls == [workout.healthKitWorkoutId!])
        #expect(harness.healthKit.finishCalls == 1)
        #expect(transports == 1)
    }

    @Test
    func metadataFailurePreservesFrozenPayloadAndNeverTransportsEarly() async throws {
        let harness = makeHarness(directory: try Fixtures.makeTempDirectory())
        let workout = Fixtures.makeWorkout(routineName: "Frozen")
        var transports = 0

        harness.healthKit.metadataError = CocoaError(.fileWriteUnknown)
        let failed = await harness.finalizer.finalize(workout, healthKit: harness.healthKit) { transports += 1 }

        guard case .healthKitFailed = failed else {
            Issue.record("expected .healthKitFailed, got \(failed)")
            return
        }
        #expect(harness.queue.entry(id: workout.id)?.phase == .awaitingHealthKitMetadata)
        #expect(harness.queue.transportEligibleEntries().isEmpty)
        #expect(transports == 0)

        // Retry with a semantically different candidate payload (same id):
        // the frozen bytes and external UUID must win.
        harness.healthKit.metadataError = nil
        let mutated = Fixtures.makeWorkout(id: workout.id, routineName: "Mutated", healthKitWorkoutId: UUID())
        let outcome = await harness.finalizer.finalize(mutated, healthKit: harness.healthKit) { transports += 1 }

        guard case .completed = outcome else {
            Issue.record("expected .completed, got \(outcome)")
            return
        }
        #expect(harness.queue.entry(id: workout.id)?.completedWorkout?.routineName == "Frozen")
        #expect(harness.healthKit.metadataCalls == [workout.healthKitWorkoutId!, workout.healthKitWorkoutId!])
        #expect(harness.healthKit.finishCalls == 1)
        #expect(transports == 1)
    }

    @Test
    func finishFailureRetriesFinishOnlyWithSameIdentifiers() async throws {
        let harness = makeHarness(directory: try Fixtures.makeTempDirectory())
        let workout = Fixtures.makeWorkout()
        var transports = 0

        harness.healthKit.finishError = CocoaError(.fileWriteUnknown)
        let failed = await harness.finalizer.finalize(workout, healthKit: harness.healthKit) { transports += 1 }

        guard case .healthKitFailed = failed else {
            Issue.record("expected .healthKitFailed, got \(failed)")
            return
        }
        #expect(harness.queue.entry(id: workout.id)?.phase == .awaitingHealthKitFinish)
        #expect(transports == 0)

        harness.healthKit.finishError = nil
        let outcome = await harness.finalizer.finalize(workout, healthKit: harness.healthKit) { transports += 1 }

        guard case .completed = outcome else {
            Issue.record("expected .completed, got \(outcome)")
            return
        }
        // Metadata phase already committed — it must not run again.
        #expect(harness.healthKit.metadataCalls.count == 1)
        #expect(harness.healthKit.finishCalls == 2)
        #expect(transports == 1)
    }

    @Test
    func duplicateEndAfterCompletionKeepsOnePayloadOneQueueEntryOneHealthKitSequence() async throws {
        let harness = makeHarness(directory: try Fixtures.makeTempDirectory())
        let workout = Fixtures.makeWorkout()
        var transports = 0

        _ = await harness.finalizer.finalize(workout, healthKit: harness.healthKit) { transports += 1 }
        let second = await harness.finalizer.finalize(workout, healthKit: harness.healthKit) { transports += 1 }

        guard case .completed = second else {
            Issue.record("expected .completed, got \(second)")
            return
        }
        #expect(harness.queue.all.count == 1)
        #expect(harness.healthKit.metadataCalls.count == 1)
        #expect(harness.healthKit.finishCalls == 1)
        // Re-triggering transport for an already-eligible entry is safe (iOS
        // dedupes on the workout id).
        #expect(transports == 2)
    }

    @Test
    func onFrozenFiresAfterEnqueueBeforeHealthKitAndUnblocksUIPromptly() async throws {
        let harness = makeHarness(directory: try Fixtures.makeTempDirectory())
        let workout = Fixtures.makeWorkout()
        var timeline: [String] = []

        let outcome = await harness.finalizer.finalize(
            workout,
            healthKit: harness.healthKit,
            onFrozen: {
                // At this point the payload must already be durable...
                timeline.append("frozen")
            },
            onTransportEligible: { timeline.append("transport") }
        )

        guard case .completed = outcome else {
            Issue.record("expected .completed, got \(outcome)")
            return
        }
        // onFrozen fires after the enqueue (entry exists) and before any
        // HealthKit call — the UI can show the summary without waiting on HK.
        #expect(timeline == ["frozen", "transport"])
        #expect(harness.queue.entry(id: workout.id) != nil)
    }

    @Test
    func onFrozenStillFiresWhenHealthKitFailsSoUIIsNeverBlocked() async throws {
        let harness = makeHarness(directory: try Fixtures.makeTempDirectory())
        let workout = Fixtures.makeWorkout()
        harness.healthKit.metadataError = CocoaError(.fileWriteUnknown)
        var frozen = false

        let outcome = await harness.finalizer.finalize(
            workout,
            healthKit: harness.healthKit,
            onFrozen: { frozen = true },
            onTransportEligible: {}
        )

        guard case .healthKitFailed = outcome else {
            Issue.record("expected .healthKitFailed, got \(outcome)")
            return
        }
        // The durable enqueue succeeded, so the summary must have been shown
        // even though HealthKit finalization failed.
        #expect(frozen)
    }

    @Test
    func onFrozenNotCalledWhenEnqueueFails() async throws {
        let dir = try Fixtures.makeTempDirectory()
        let harness = makeHarness(directory: dir)
        let restore = try Fixtures.makeReadOnly(dir)
        defer { restore() }
        var frozen = false

        let outcome = await harness.finalizer.finalize(
            Fixtures.makeWorkout(),
            healthKit: harness.healthKit,
            onFrozen: { frozen = true },
            onTransportEligible: {}
        )

        guard case .notEnqueued = outcome else {
            Issue.record("expected .notEnqueued, got \(outcome)")
            return
        }
        #expect(!frozen)
    }

    @Test
    func queueWriteFailureAbortsWithNoExternalSideEffect() async throws {
        let dir = try Fixtures.makeTempDirectory()
        let harness = makeHarness(directory: dir)
        let restore = try Fixtures.makeReadOnly(dir)
        defer { restore() }
        let workout = Fixtures.makeWorkout()
        var transports = 0

        let outcome = await harness.finalizer.finalize(workout, healthKit: harness.healthKit) { transports += 1 }

        guard case .notEnqueued = outcome else {
            Issue.record("expected .notEnqueued, got \(outcome)")
            return
        }
        #expect(harness.queue.all.isEmpty)
        #expect(harness.healthKit.metadataCalls.isEmpty)
        #expect(harness.healthKit.finishCalls == 0)
        #expect(transports == 0)
    }

    @Test
    func uiTestingPathWithoutHealthKitStillReachesTransportEligible() async throws {
        let harness = makeHarness(directory: try Fixtures.makeTempDirectory())
        let workout = Fixtures.makeWorkout()
        var transports = 0

        let outcome = await harness.finalizer.finalize(workout, healthKit: nil) { transports += 1 }

        guard case .completed = outcome else {
            Issue.record("expected .completed, got \(outcome)")
            return
        }
        #expect(harness.queue.entry(id: workout.id)?.phase == .transportEligible)
        #expect(transports == 1)
    }
}
