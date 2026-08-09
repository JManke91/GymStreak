//
//  WatchHistoryTemplateSplitTests.swift
//  GymStreakTests
//
//  Split of workout history from template intent
//  (`docs/adr/0001-split-workout-history-from-template-intent.md`). Four seams:
//    • the wire contract of the new template-only kind and its identity rules;
//    • the durable sync entries it produces on the watch — reached through the
//      iOS-target copy, since there is no watch unit-test target — where the
//      two entries for one workout must never collapse into one;
//    • the watch EMIT half (ticket 02): one atomic enqueue producing both
//      entries, and the liveness property the whole split exists for — a
//      template transaction that can never be acknowledged withholds no
//      workout history;
//    • the iOS receive pipeline: both arrival orders converge, the legacy fused
//      kind is untouched, and the two payloads never answer each other's
//      acknowledgment.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

// MARK: - Wire contract

@Suite(.serialized)
@MainActor
struct WatchHistoryTemplateSplitWireTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures

    @Test
    func splitEnvelopeCarriesTheWorkoutWithoutClaimingItsHistory() throws {
        let workout = makeTemplateWorkout()
        let envelope = TemplateTransactionEnvelope(templateIntentFor: workout)

        let decoded = try JSONDecoder().decode(
            TemplateTransactionEnvelope.self, from: JSONEncoder().encode(envelope)
        )

        // `completedWorkout` means "this carries history" and must stay nil, or
        // the derived entry `workoutID` collides with the history entry's.
        #expect(decoded.completedWorkout == nil)
        #expect(decoded.workoutID == nil)
        #expect(decoded.templateIntentWorkout?.id == workout.id)
        #expect(decoded.payload.templateIntentWorkout?.exercises.count == 1)
        #expect(decoded.transactionID == workout.templateTransactionID)
        #expect(decoded.sequence == workout.templateSequence)
        #expect(decoded.isInternallyConsistent)
    }

    @Test
    func splitEnvelopeWithAWorkoutCorrelationIsInconsistent() {
        let workout = makeTemplateWorkout()
        let envelope = TemplateTransactionEnvelope(
            transactionID: workout.templateTransactionID!,
            senderEpoch: workout.templateSenderEpoch!,
            routineID: workout.routineId,
            sequence: workout.templateSequence!,
            workoutID: workout.id,
            payload: .workoutTemplateIntent(WatchWorkoutTemplateIntent(workout: workout))
        )
        #expect(!envelope.isInternallyConsistent)
    }

    @Test
    func splitEnvelopeWithAForeignOrderingIdentityIsInconsistent() {
        let workout = makeTemplateWorkout()
        let envelope = TemplateTransactionEnvelope(
            transactionID: UUID(),
            senderEpoch: workout.templateSenderEpoch!,
            routineID: workout.routineId,
            sequence: workout.templateSequence!,
            workoutID: nil,
            payload: .workoutTemplateIntent(WatchWorkoutTemplateIntent(workout: workout))
        )
        #expect(!envelope.isInternallyConsistent)
    }

    @Test
    func legacyFusedEnvelopeRulesAreUnchanged() {
        let workout = makeTemplateWorkout()
        #expect(TemplateTransactionEnvelope(completedWorkout: workout).isInternallyConsistent)

        // A fused payload whose envelope correlation disagrees with its own
        // workout is still rejected.
        let disagreeing = TemplateTransactionEnvelope(
            transactionID: workout.templateTransactionID!,
            senderEpoch: workout.templateSenderEpoch!,
            routineID: workout.routineId,
            sequence: workout.templateSequence!,
            workoutID: UUID(),
            payload: .completedWorkoutUpdate(workout)
        )
        #expect(!disagreeing.isInternallyConsistent)
    }

    @Test
    func inboxStoresTheNewKindAndRejectsAnInconsistentOne() throws {
        let inbox = WatchWorkoutInboxStore(
            directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil
        )
        let workout = makeTemplateWorkout()
        let envelope = TemplateTransactionEnvelope(templateIntentFor: workout)

        try inbox.store(
            transactionData: try JSONEncoder().encode(envelope),
            transactionID: envelope.transactionID
        )
        let entry = try #require(inbox.entries().first)
        #expect(entry.identifier == envelope.transactionID)
        #expect(entry.completedWorkout == nil)
        #expect(entry.transaction?.templateIntentWorkout?.id == workout.id)

        let inconsistent = TemplateTransactionEnvelope(
            transactionID: envelope.transactionID,
            senderEpoch: envelope.senderEpoch,
            routineID: envelope.routineID,
            sequence: envelope.sequence,
            workoutID: workout.id,
            payload: .workoutTemplateIntent(WatchWorkoutTemplateIntent(workout: workout))
        )
        #expect(throws: (any Error).self) {
            try inbox.store(
                transactionData: try JSONEncoder().encode(inconsistent),
                transactionID: inconsistent.transactionID
            )
        }
    }

    private func makeTemplateWorkout() -> CompletedWatchWorkout {
        WatchHistoryTemplateSplitFixtures.makeTemplateWorkout()
    }
}

// MARK: - Durable sync entries (watch)

@Suite(.serialized)
@MainActor
struct WatchHistoryTemplateSplitEntryTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures

    @Test
    func historyAndTemplateEntriesForOneWorkoutStayDistinct() throws {
        let directory = try Fixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workout = WatchHistoryTemplateSplitFixtures.makeTemplateWorkout()
        let split = WatchHistoryTemplateSplitFixtures.split(workout)
        try WatchHistoryTemplateSplitFixtures.seedQueue(
            [split.historyEntry, split.templateEntry], in: directory
        )

        let store = WatchSyncStateStore(directory: directory, legacyDefaults: nil)

        // The trap this kind exists to avoid: `entry(id:)` matches on workoutID
        // as well as the entry id, so a template envelope correlating the
        // workout would make one of these two entries unreachable.
        #expect(store.all.count == 2)
        #expect(store.entry(id: workout.id)?.id == workout.id)
        #expect(store.entry(id: split.transactionID)?.id == split.transactionID)
        #expect(store.all.first { $0.id == split.transactionID }?.workoutID == nil)

        // Only the template entry carries template intent, so only it is
        // gated on the routine's queue head.
        let history = try #require(store.all.first { $0.id == workout.id })
        #expect(!history.hasTemplateIntent)
        #expect(history.workoutID == workout.id)
    }

    @Test
    func pendingSplitTemplateIntentStillShowsAsOptimisticOverlay() throws {
        let directory = try Fixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let slotID = UUID(), setID = UUID()
        let routine = Fixtures.makeWatchRoutine(
            exerciseId: slotID, setId: setID, reps: 10, weight: 60
        )
        let workout = WatchHistoryTemplateSplitFixtures.makeTemplateWorkout(
            routineID: routine.id, slotID: slotID, setID: setID, actualReps: 12, actualWeight: 65
        )
        let split = WatchHistoryTemplateSplitFixtures.split(workout)
        try WatchHistoryTemplateSplitFixtures.seedQueue(
            [split.historyEntry, split.templateEntry], in: directory
        )

        let store = WatchSyncStateStore(directory: directory, legacyDefaults: nil)
        store.applyRoutineContext([routine], header: nil)

        let effective = try #require(store.effectiveRoutines().first)
        let set = try #require(effective.exercises.first?.sets.first)
        #expect(set.reps == 12)
        #expect(set.weight == 65)
    }
}

// MARK: - Watch emit (one atomic enqueue, two entries)

@MainActor
private final class SplitRecordingTransport: WatchWorkoutTransporting {
    var isWorkoutTransportActivated = true
    var isWorkoutMessageReachable = false
    var outstandingWorkoutSemanticIDs: Set<UUID> = []
    private(set) var transfers: [[String: Any]] = []

    func sendWorkoutMessage(_ payload: [String: Any]) {}

    func enqueueWorkoutUserInfo(_ payload: [String: Any]) {
        transfers.append(payload)
    }

    var transportedWorkoutIDs: [UUID] {
        transfers.compactMap {
            ($0[WatchWorkoutWire.workoutIdKey] as? String).flatMap(UUID.init(uuidString:))
        }
    }

    var transportedTransactionIDs: [UUID] {
        transfers.compactMap {
            ($0[WatchWorkoutWire.transactionIdKey] as? String).flatMap(UUID.init(uuidString:))
        }
    }
}

@MainActor
private final class SplitFinalizationHealthKit: WorkoutFinalizationHealthKit {
    func endCollectionAndAddMetadata(externalId: UUID) async throws {}
    func finishWorkout() async throws {}
}

@Suite(.serialized)
@MainActor
struct WatchHistoryTemplateSplitEnqueueTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures

    /// A workout for `routine` that performed 12 × `actualWeight` against a
    /// planned 10 × 60, requesting the template update.
    private func makeTemplateWorkout(
        for routine: WatchRoutine, actualWeight: Double = 65
    ) -> CompletedWatchWorkout {
        Fixtures.makeWorkout(
            routineId: routine.id,
            shouldUpdateTemplate: true,
            exercises: [Fixtures.makeExercise(
                id: routine.exercises[0].id,
                sets: [Fixtures.makeSet(
                    id: routine.exercises[0].sets[0].id,
                    plannedReps: 10, actualReps: 12, plannedWeight: 60, actualWeight: actualWeight
                )]
            )]
        )
    }

    @Test
    func templateCarryingWorkoutEnqueuesHistoryAndTemplateInOneCommit() throws {
        let directory = try Fixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatchSyncStateStore(directory: directory, legacyDefaults: nil)
        let routine = Fixtures.makeWatchRoutine()
        var workout = makeTemplateWorkout(for: routine)
        workout.addedRoutineExerciseIDs = [routine.exercises[0].id]
        workout.overloadAppliedExerciseIDs = [routine.exercises[0].id]

        let history = try store.enqueue(
            workout, phase: .awaitingHealthKitMetadata, routineAnchor: routine
        )

        // The finalizer sequences HealthKit on the returned entry, so it must be
        // the history half — and that half must look like an ordinary
        // no-template workout, or iOS would route it back into the template path.
        #expect(history.id == workout.id)
        #expect(history.workoutID == workout.id)
        #expect(!history.hasTemplateIntent)
        #expect(history.phase == .awaitingHealthKitMetadata)
        let frozen = try #require(history.completedWorkout)
        #expect(frozen.shouldUpdateTemplate == false)
        #expect(frozen.templateTransactionID == nil)
        #expect(frozen.templateSenderEpoch == nil)
        #expect(frozen.templateSequence == nil)
        // Everything iOS needs to RECORD the workout is retained.
        #expect(frozen.healthKitWorkoutId == workout.healthKitWorkoutId)
        #expect(frozen.exercises.count == 1)
        #expect(frozen.endTime == workout.endTime)
        #expect(frozen.addedRoutineExerciseIDs == [routine.exercises[0].id])
        #expect(frozen.overloadAppliedExerciseIDs == [routine.exercises[0].id])

        // The template half keeps the ordering identity and no workout
        // correlation, and needs no HealthKit finalization of its own.
        let template = try #require(Fixtures.templateEntry(in: store, forWorkout: workout.id))
        #expect(template.workoutID == nil)
        #expect(template.id == template.templateTransaction?.transactionID)
        #expect(template.hasTemplateIntent)
        #expect(template.phase == .transportEligible)
        #expect(template.templateTransaction?.sequence == 0)
        #expect(template.templateTransaction?.isInternallyConsistent == true)
        #expect(template.templateTransaction?.templateIntentWorkout?.shouldUpdateTemplate == true)

        // One commit: both halves are durable together, and a retry re-enters on
        // the frozen history entry without enqueuing a third.
        let reloaded = WatchSyncStateStore(directory: directory, legacyDefaults: nil)
        #expect(reloaded.all.count == 2)
        let retried = try reloaded.enqueue(workout, phase: .awaitingHealthKitMetadata)
        #expect(retried.id == workout.id)
        #expect(reloaded.all.count == 2)
    }

    @Test
    func aFailedCommitEnqueuesNeitherHalfAndConsumesNoSequence() throws {
        let directory = try Fixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatchSyncStateStore(directory: directory, legacyDefaults: nil)
        let routine = Fixtures.makeWatchRoutine()
        let restore = try Fixtures.makeReadOnly(directory)

        #expect(throws: (any Error).self) {
            try store.enqueue(makeTemplateWorkout(for: routine), phase: .awaitingHealthKitMetadata)
        }
        #expect(store.all.isEmpty)

        restore()
        let reloaded = WatchSyncStateStore(directory: directory, legacyDefaults: nil)
        #expect(reloaded.all.isEmpty)
        let next = makeTemplateWorkout(for: routine)
        try reloaded.enqueue(next, phase: .transportEligible)
        #expect(Fixtures.templateEntry(in: reloaded, forWorkout: next.id)?
            .templateTransaction?.sequence == 0)
    }

    @Test
    func aWorkoutWithoutTemplateIntentStillEnqueuesExactlyOneEntry() throws {
        let directory = try Fixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatchSyncStateStore(directory: directory, legacyDefaults: nil)
        let workout = Fixtures.makeWorkout()

        let entry = try store.enqueue(workout, phase: .awaitingHealthKitMetadata)

        #expect(store.all.count == 1)
        #expect(entry.id == workout.id)
        #expect(entry.templateTransaction == nil)
        #expect(entry.completedWorkout?.shouldUpdateTemplate == false)
        #expect(store.transportEligibleEntries().isEmpty)
    }

    @Test
    func finalizingATemplateWorkoutFreezesBothHalvesAndPhasesOnlyTheHistory() async throws {
        let directory = try Fixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatchSyncStateStore(directory: directory, legacyDefaults: nil)
        let routine = Fixtures.makeWatchRoutine()
        let workout = makeTemplateWorkout(for: routine)
        var transports = 0

        let outcome = await WatchWorkoutFinalizer(syncState: store).finalize(
            workout,
            healthKit: SplitFinalizationHealthKit(),
            routineAnchor: routine,
            onTransportEligible: { transports += 1 }
        )

        guard case .completed = outcome else {
            Issue.record("expected .completed, got \(outcome)")
            return
        }
        #expect(store.all.count == 2)
        // `advance(id:)` matches the workout id, which only the history half
        // owns — the template half was already eligible.
        #expect(store.entry(id: workout.id)?.phase == .transportEligible)
        #expect(Fixtures.templateEntry(in: store, forWorkout: workout.id)?.phase == .transportEligible)
        #expect(transports == 1)
    }

    /// The 2026-08-01 incident as a regression test: a template transaction
    /// nothing will ever acknowledge pins its routine's queue head, and a later
    /// workout for that same routine must still reach the iPhone.
    @Test
    func aStalledTemplateHeadNoLongerWithholdsALaterWorkoutsHistory() throws {
        let directory = try Fixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatchSyncStateStore(directory: directory, legacyDefaults: nil)
        let routine = Fixtures.makeWatchRoutine()
        let stalled = makeTemplateWorkout(for: routine, actualWeight: 65)
        let later = makeTemplateWorkout(for: routine, actualWeight: 70)
        try store.enqueue(stalled, phase: .transportEligible, routineAnchor: routine)
        try store.enqueue(later, phase: .transportEligible, routineAnchor: routine)

        let transport = SplitRecordingTransport()
        let coordinator = WatchWorkoutTransportCoordinator(syncState: store, transport: transport)
        // No acknowledgment ever arrives for the head transaction.
        coordinator.reconcile()

        #expect(Set(transport.transportedWorkoutIDs) == [stalled.id, later.id])
        // Only the head's template intent went; the successor's is still gated,
        // which is exactly the cost the split makes acceptable.
        let stalledTemplate = try #require(Fixtures.templateEntry(in: store, forWorkout: stalled.id))
        let laterTemplate = try #require(Fixtures.templateEntry(in: store, forWorkout: later.id))
        #expect(transport.transportedTransactionIDs == [stalledTemplate.id])
        #expect(!transport.transportedTransactionIDs.contains(laterTemplate.id))
    }

    @Test
    func theAcceptedChangeShowsImmediatelyAndRevertsWhenTheTemplateIntentDies() throws {
        let directory = try Fixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatchSyncStateStore(directory: directory, legacyDefaults: nil)
        let routine = Fixtures.makeWatchRoutine(reps: 10, weight: 60)
        store.applyRoutineContext([routine], header: nil)
        let workout = makeTemplateWorkout(for: routine, actualWeight: 65)
        try store.enqueue(workout, phase: .transportEligible, routineAnchor: routine)

        // The overlay comes from the template half; the history half never folds.
        #expect(store.effectiveRoutines()[0].exercises[0].sets[0].weight == 65)
        #expect(store.effectiveRoutines()[0].exercises[0].sets[0].reps == 12)

        let template = try #require(Fixtures.templateEntry(in: store, forWorkout: workout.id))
        store.quarantine(id: template.id, reason: "payload permanently untransportable")

        // A dead template intent stops prescribing values — and takes no
        // workout history with it.
        #expect(store.effectiveRoutines()[0].exercises[0].sets[0].weight == 60)
        #expect(store.entry(id: workout.id)?.phase == .transportEligible)
    }
}

// MARK: - iOS receive pipeline

@Suite(.serialized)
@MainActor
struct WatchHistoryTemplateSplitIngestionTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures

    @MainActor
    private struct Harness {
        let container: ModelContainer
        let context: ModelContext
        let inbox: WatchWorkoutInboxStore
        let receipts: WorkoutIngestReceiptStore
        let watchSync: MockWatchSyncServicing
        let coordinator: WatchWorkoutIngestionCoordinator
        let routineRepository: SwiftDataRoutineRepository
        let sessionRepository: SwiftDataWorkoutSessionRepository

        func deliver(history workout: CompletedWatchWorkout) throws {
            try inbox.store(payloadData: try JSONEncoder().encode(workout), workoutId: workout.id)
        }

        func deliver(transaction envelope: TemplateTransactionEnvelope) throws {
            try inbox.store(
                transactionData: try JSONEncoder().encode(envelope),
                transactionID: envelope.transactionID
            )
        }

        func sessions() -> [WorkoutSession] { sessionRepository.fetchAll() }

        func committedSet(routineId: UUID) throws -> (reps: Int, weight: Double) {
            let fresh = ModelContext(container)
            let routine = try #require(
                SwiftDataRoutineRepository(modelContext: fresh).fetch(id: routineId)
            )
            let set = try #require(routine.routineExercisesList.first?.setsList.first)
            return (set.reps, set.weight)
        }
    }

    private func makeHarness() throws -> Harness {
        let container = InMemoryModelContainer.make()
        let context = container.mainContext
        let inbox = WatchWorkoutInboxStore(
            directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil
        )
        let receipts = WorkoutIngestReceiptStore(directory: try Fixtures.makeTempDirectory())
        let watchSync = MockWatchSyncServicing()
        let coordinator = WatchWorkoutIngestionCoordinator(
            inbox: inbox,
            receipts: receipts,
            historyTransactions: SwiftDataWorkoutHistoryTransactionFactory(container: container),
            routineSnapshots: SwiftDataAuthoritativeRoutineSnapshotProvider(container: container),
            routineSnapshotTransport: watchSync,
            mainContextCache: SwiftDataMainContextRoutineCacheRefresher(modelContext: context),
            watchSync: watchSync
        )
        return Harness(
            container: container, context: context, inbox: inbox, receipts: receipts,
            watchSync: watchSync, coordinator: coordinator,
            routineRepository: SwiftDataRoutineRepository(modelContext: context),
            sessionRepository: SwiftDataWorkoutSessionRepository(modelContext: context)
        )
    }

    /// A routine with one exercise and one set at 10 × 60 kg, plus the workout
    /// the watch would report for it (12 × 65 performed).
    private func seed(
        _ harness: Harness, sequence: UInt64 = 0, senderEpoch: UUID = UUID()
    ) throws -> (routine: Routine, workout: CompletedWatchWorkout) {
        let exercise = Exercise(name: "Bench Press")
        let routine = Routine(name: "Push Day")
        let routineExercise = RoutineExercise(exercise: exercise, order: 0)
        routineExercise.routine = routine
        let set = ExerciseSet(reps: 10, weight: 60, restTime: 60, order: 0)
        set.routineExercise = routineExercise
        routineExercise.sets?.append(set)
        routine.routineExercises?.append(routineExercise)
        harness.context.insert(exercise)
        harness.context.insert(routine)
        try harness.context.save()

        let workout = WatchHistoryTemplateSplitFixtures.makeTemplateWorkout(
            routineID: routine.id, slotID: routineExercise.id, setID: set.id,
            exerciseID: exercise.id, senderEpoch: senderEpoch, sequence: sequence
        )
        return (routine, workout)
    }

    @Test
    func templateAfterHistoryAppliesTheRoutineUpdateAndDuplicatesNoHistory() throws {
        let harness = try makeHarness()
        let (routine, workout) = try seed(harness)
        let split = WatchHistoryTemplateSplitFixtures.split(workout)

        try harness.deliver(history: split.history)
        harness.coordinator.drainInbox()
        #expect(harness.sessions().count == 1)
        #expect(try harness.committedSet(routineId: routine.id).weight == 60)

        try harness.deliver(transaction: split.envelope)
        harness.coordinator.drainInbox()

        // Template applied, and exactly one history row for the workout.
        let committed = try harness.committedSet(routineId: routine.id)
        #expect(committed.reps == 12)
        #expect(committed.weight == 65)
        #expect(harness.sessions().count == 1)
        #expect(harness.sessions().first?.id == workout.id)
        #expect(harness.sessions().first?.didUpdateTemplate == true)

        // The history entry keeps its own plain acknowledgment; the template
        // entry gets the versioned terminal one, correlated to no workout.
        #expect(harness.watchSync.acknowledgeWorkoutSavedCalls == [workout.id])
        let ack = try #require(harness.watchSync.templateAcks.first)
        #expect(ack.transactionID == split.transactionID)
        #expect(ack.outcome == .applied)
        #expect(ack.workoutId == nil)
        #expect(harness.inbox.entries().isEmpty)

        // Identity separation in the receipt ledger: the workout id still
        // resolves to the history receipt, never to the template one.
        #expect(harness.receipts.receipt(for: workout.id)?.phase == .readyToAcknowledgeNotRequested)
        #expect(harness.receipts.receipt(for: workout.id)?.transactionID == nil)
    }

    @Test
    func templateBeforeHistoryCommitsTheWrappedWorkoutAndTheHistoryEntryStillRetires() throws {
        let harness = try makeHarness()
        let (routine, workout) = try seed(harness)
        let split = WatchHistoryTemplateSplitFixtures.split(workout)

        try harness.deliver(transaction: split.envelope)
        harness.coordinator.drainInbox()

        // The wrapped copy commits the history the separate entry has not
        // delivered yet, so nothing waits on arrival order.
        #expect(harness.sessions().count == 1)
        #expect(harness.sessions().first?.id == workout.id)
        #expect(try harness.committedSet(routineId: routine.id).weight == 65)
        #expect(harness.watchSync.templateAcks.count == 1)
        #expect(harness.watchSync.acknowledgeWorkoutSavedCalls.isEmpty)

        try harness.deliver(history: split.history)
        harness.coordinator.drainInbox()

        // No second row, and the history entry gets the plain acknowledgment
        // it needs to retire on the watch.
        #expect(harness.sessions().count == 1)
        #expect(harness.watchSync.acknowledgeWorkoutSavedCalls == [workout.id])
        #expect(harness.watchSync.templateAcks.count == 1)
        #expect(harness.inbox.entries().isEmpty)
    }

    @Test
    func redeliveredTemplateIsAnsweredFromItsReceiptWithoutReapplying() throws {
        let harness = try makeHarness()
        let (routine, workout) = try seed(harness)
        let split = WatchHistoryTemplateSplitFixtures.split(workout)

        try harness.deliver(transaction: split.envelope)
        harness.coordinator.drainInbox()

        // The user then edits the same set on iPhone. A redelivery must not
        // replay the watch's values over it.
        let live = try #require(harness.routineRepository.fetch(id: routine.id))
        try #require(live.routineExercisesList.first?.setsList.first).weight = 80
        try harness.routineRepository.save()

        try harness.deliver(transaction: split.envelope)
        harness.coordinator.drainInbox()

        #expect(try harness.committedSet(routineId: routine.id).weight == 80)
        #expect(harness.sessions().count == 1)
        #expect(harness.watchSync.templateAcks.count == 2)
        #expect(harness.watchSync.templateAcks.allSatisfy { $0.transactionID == split.transactionID })
    }

    @Test
    func legacyFusedTransactionIngestsExactlyAsBefore() throws {
        let harness = try makeHarness()
        let (routine, workout) = try seed(harness)

        try harness.deliver(transaction: TemplateTransactionEnvelope(completedWorkout: workout))
        harness.coordinator.drainInbox()

        #expect(harness.sessions().count == 1)
        #expect(harness.sessions().first?.didUpdateTemplate == true)
        #expect(try harness.committedSet(routineId: routine.id).weight == 65)
        let ack = try #require(harness.watchSync.templateAcks.first)
        #expect(ack.outcome == .applied)
        // The fused kind still correlates its workout, so an older watch reads
        // the same acknowledgment as a plain one.
        #expect(ack.workoutId == workout.id)
        #expect(harness.receipts.receipt(for: workout.id)?.transactionID == workout.templateTransactionID)
    }

    @Test
    func aSplitTemplateBuffersUntilItsPredecessorArrives() throws {
        let harness = try makeHarness()
        let senderEpoch = UUID()
        let (routine, first) = try seed(harness, sequence: 0, senderEpoch: senderEpoch)
        let live = try #require(harness.routineRepository.fetch(id: routine.id))
        let slot = try #require(live.routineExercisesList.first)
        let setID = try #require(slot.setsList.first).id
        func successor(actualWeight: Double, sequence: UInt64) -> TemplateTransactionEnvelope {
            WatchHistoryTemplateSplitFixtures.split(
                WatchHistoryTemplateSplitFixtures.makeTemplateWorkout(
                    routineID: routine.id, slotID: slot.id, setID: setID,
                    exerciseID: slot.exercise!.id, actualWeight: actualWeight,
                    senderEpoch: senderEpoch, sequence: sequence
                )
            ).envelope
        }

        // Establish the per-routine ledger with the head transaction.
        try harness.deliver(transaction: WatchHistoryTemplateSplitFixtures.split(first).envelope)
        harness.coordinator.drainInbox()
        #expect(try harness.committedSet(routineId: routine.id).weight == 65)

        // A later transaction overtakes its predecessor (cross-channel
        // delivery is not causally ordered): it stays durably inboxed and
        // mutates nothing.
        try harness.deliver(transaction: successor(actualWeight: 75, sequence: 2))
        harness.coordinator.drainInbox()
        #expect(try harness.committedSet(routineId: routine.id).weight == 65)
        #expect(harness.inbox.entries().count == 1)
        #expect(harness.watchSync.templateAcks.count == 1)

        // The predecessor's arrival releases it within the same drain.
        try harness.deliver(transaction: successor(actualWeight: 70, sequence: 1))
        harness.coordinator.drainInbox()

        #expect(try harness.committedSet(routineId: routine.id).weight == 75)
        #expect(harness.inbox.entries().isEmpty)
        #expect(harness.watchSync.templateAcks.count == 3)
    }
}

// MARK: - Fixtures

@MainActor
enum WatchHistoryTemplateSplitFixtures {
    /// The two payloads the watch emits for one template-carrying workout: an
    /// ordinary no-template history copy (ungated, retired by the plain
    /// acknowledgment) and the template intent wrapping the same workout.
    struct Split {
        let history: CompletedWatchWorkout
        let envelope: TemplateTransactionEnvelope

        var transactionID: UUID { envelope.transactionID }
        var historyEntry: OutgoingSyncEntry {
            OutgoingSyncEntry(
                payload: .completedWorkout(history), phase: .transportEligible,
                enqueuedAt: Date(timeIntervalSince1970: 1_700_000_700),
                quarantineReason: nil, heldAck: nil
            )
        }
        var templateEntry: OutgoingSyncEntry {
            OutgoingSyncEntry(
                payload: .templateTransaction(envelope), phase: .transportEligible,
                enqueuedAt: Date(timeIntervalSince1970: 1_700_000_701),
                quarantineReason: nil, heldAck: nil
            )
        }
    }

    static func makeTemplateWorkout(
        id: UUID = UUID(),
        routineID: UUID = UUID(),
        slotID: UUID = UUID(),
        setID: UUID = UUID(),
        exerciseID: UUID = UUID(),
        actualReps: Int = 12,
        actualWeight: Double = 65,
        senderEpoch: UUID = UUID(),
        sequence: UInt64 = 0
    ) -> CompletedWatchWorkout {
        WatchWorkoutSyncFixtures.makeWorkout(
            id: id,
            routineId: routineID,
            shouldUpdateTemplate: true,
            exercises: [WatchWorkoutSyncFixtures.makeExercise(
                id: slotID,
                exerciseId: exerciseID,
                sets: [WatchWorkoutSyncFixtures.makeSet(
                    id: setID, plannedReps: 10, actualReps: actualReps,
                    plannedWeight: 60, actualWeight: actualWeight
                )]
            )],
            transactionID: UUID(),
            senderEpoch: senderEpoch,
            sequence: sequence
        )
    }

    /// Splits a template-carrying workout the way ticket 02's enqueue will:
    /// the history copy drops the template intent entirely (it is an ordinary
    /// workout payload older builds already understand), and the template
    /// envelope keeps the ordering identity with a nil `workoutID`.
    static func split(_ workout: CompletedWatchWorkout) -> Split {
        Split(
            history: WatchWorkoutSyncFixtures.makeWorkout(
                id: workout.id,
                routineId: workout.routineId,
                routineName: workout.routineName,
                shouldUpdateTemplate: false,
                healthKitWorkoutId: workout.healthKitWorkoutId,
                exercises: workout.exercises,
                endTime: workout.endTime
            ),
            envelope: TemplateTransactionEnvelope(templateIntentFor: workout)
        )
    }

    /// Writes a durable outgoing queue containing exactly these entries, so a
    /// store can be opened over the two entries ticket 02's atomic enqueue will
    /// produce. A format change fails loudly: the store quarantines an
    /// undecodable state file and starts empty.
    static func seedQueue(_ entries: [OutgoingSyncEntry], in directory: URL) throws {
        let encoded = String(decoding: try JSONEncoder().encode(entries), as: UTF8.self)
        try Data(#"{"version":3,"entries":\#(encoded)}"#.utf8)
            .write(to: directory.appendingPathComponent("outgoing-queue.json"), options: .atomic)
    }
}
