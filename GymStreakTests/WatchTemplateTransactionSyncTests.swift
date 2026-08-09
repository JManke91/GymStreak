//
//  WatchTemplateTransactionSyncTests.swift
//  GymStreakTests
//
//  Covers the watch-side half of ticket 05: transaction identity allocation
//  in the same atomic commit as the enqueue, the per-routine ordering gate,
//  optimistic folding over the authoritative base, ack/context convergence in
//  either arrival order, plain-ack retention for template intent, legacy
//  migration, and the iOS routine authority's epoch/generation rules. The
//  watch files are identical copies in both targets, so these tests stand in
//  for the missing watch unit-test target.
//
//  Since the history/template split (ADR 0001), enqueuing a template-carrying
//  workout produces TWO entries and returns the history one, so every
//  transaction assertion here reaches for the template half explicitly
//  (`Fixtures.templateEntry(in:forWorkout:)` / `pendingTemplateEntries`). The
//  ungated history halves are covered in `WatchHistoryTemplateSplitTests`.
//

import Foundation
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct WatchTemplateTransactionSyncTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures

    /// The unretired template transactions, in FIFO order — what `store.all`
    /// meant for these tests before the split added an ungated history entry
    /// alongside every template-carrying workout.
    private func pendingTemplateEntries(_ store: WatchSyncStateStore) -> [OutgoingSyncEntry] {
        store.all.filter(\.hasTemplateIntent)
    }

    // MARK: - Transaction identity

    @Test
    func templateEnqueueAllocatesStableIdentityAndPersistsIt() throws {
        let dir = try Fixtures.makeTempDirectory()
        let store = WatchSyncStateStore(directory: dir, legacyDefaults: nil)
        let routineId = UUID()
        let firstWorkout = Fixtures.makeWorkout(routineId: routineId, shouldUpdateTemplate: true)
        let secondWorkout = Fixtures.makeWorkout(routineId: routineId, shouldUpdateTemplate: true)

        try store.enqueue(firstWorkout, phase: .transportEligible)
        try store.enqueue(secondWorkout, phase: .transportEligible)

        let first = try #require(
            Fixtures.templateEntry(in: store, forWorkout: firstWorkout.id)?.templateTransaction
        )
        let second = try #require(
            Fixtures.templateEntry(in: store, forWorkout: secondWorkout.id)?.templateTransaction
        )
        #expect(first.sequence == 0)
        #expect(second.sequence == 1)
        // One persistent sender epoch is shared by every template transaction.
        #expect(first.senderEpoch == second.senderEpoch)

        // Identity survives relaunch, and the counter continues from the file.
        let reloaded = WatchSyncStateStore(directory: dir, legacyDefaults: nil)
        #expect(Fixtures.templateEntry(in: reloaded, forWorkout: firstWorkout.id)?
            .templateTransaction?.transactionID == first.transactionID)
        let thirdWorkout = Fixtures.makeWorkout(routineId: routineId, shouldUpdateTemplate: true)
        try reloaded.enqueue(thirdWorkout, phase: .transportEligible)
        let third = try #require(
            Fixtures.templateEntry(in: reloaded, forWorkout: thirdWorkout.id)?.templateTransaction
        )
        #expect(third.sequence == 2)
        #expect(third.senderEpoch == first.senderEpoch)
    }

    @Test
    func sequencesAreAllocatedPerRoutineAndNoTemplateWorkoutsGetNoIdentity() throws {
        let store = WatchSyncStateStore(directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil)
        let routineA = UUID()
        let routineB = UUID()
        let a0 = Fixtures.makeWorkout(routineId: routineA, shouldUpdateTemplate: true)
        let b0 = Fixtures.makeWorkout(routineId: routineB, shouldUpdateTemplate: true)
        let plain = Fixtures.makeWorkout(routineId: routineA)

        try store.enqueue(a0, phase: .transportEligible)
        try store.enqueue(b0, phase: .transportEligible)
        let plainEntry = try store.enqueue(plain, phase: .transportEligible)

        #expect(Fixtures.templateEntry(in: store, forWorkout: a0.id)?.templateTransaction?.sequence == 0)
        #expect(Fixtures.templateEntry(in: store, forWorkout: b0.id)?.templateTransaction?.sequence == 0)
        // A workout that requests no template update stays a single entry.
        #expect(plainEntry.templateTransaction == nil)
        #expect(Fixtures.templateEntry(in: store, forWorkout: plain.id) == nil)
        #expect(store.all.count == 5)
    }

    @Test
    func queueWriteFailureAllocatesNothing() throws {
        let dir = try Fixtures.makeTempDirectory()
        let store = WatchSyncStateStore(directory: dir, legacyDefaults: nil)
        let restore = try Fixtures.makeReadOnly(dir)
        defer { restore() }

        #expect(throws: Error.self) {
            try store.enqueue(Fixtures.makeWorkout(shouldUpdateTemplate: true), phase: .transportEligible)
        }
        // Neither half of the split was enqueued — the two entries commit or
        // fail together.
        #expect(store.all.isEmpty)
        restore()

        // The failed attempt consumed no sequence: the next one still gets 0.
        let routineId = UUID()
        let workout = Fixtures.makeWorkout(routineId: routineId, shouldUpdateTemplate: true)
        try store.enqueue(workout, phase: .transportEligible)
        #expect(Fixtures.templateEntry(in: store, forWorkout: workout.id)?
            .templateTransaction?.sequence == 0)
    }

    @Test
    func legacyQueuedTemplateEntriesGetIdentityInFIFOOrder() throws {
        let dir = try Fixtures.makeTempDirectory()
        let (defaults, suiteName) = Fixtures.makeDefaultsSuite()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let routineId = UUID()
        let legacy = [
            Fixtures.makeWorkout(routineId: routineId, shouldUpdateTemplate: true),
            Fixtures.makeWorkout(routineId: routineId, shouldUpdateTemplate: true),
            Fixtures.makeWorkout(routineId: routineId)
        ]
        defaults.set(try JSONEncoder().encode(legacy), forKey: WatchSyncStateStore.legacyDefaultsKey)

        let store = WatchSyncStateStore(directory: dir, legacyDefaults: defaults)

        #expect(store.all.compactMap(\.completedWorkout).map(\.id) == legacy.map(\.id))
        #expect(store.all[0].templateTransaction?.sequence == 0)
        #expect(store.all[1].templateTransaction?.sequence == 1)
        #expect(store.all[2].templateTransaction == nil)
        #expect(store.all[0].templateTransaction?.senderEpoch == store.all[1].templateTransaction?.senderEpoch)
    }

    @Test
    func failedLegacyMigrationPublishesAndTransportsNothingUntilAtomicRetrySucceeds() throws {
        let dir = try Fixtures.makeTempDirectory()
        let (defaults, suiteName) = Fixtures.makeDefaultsSuite()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacy = Fixtures.makeWorkout(shouldUpdateTemplate: true)
        defaults.set(try JSONEncoder().encode([legacy]), forKey: WatchSyncStateStore.legacyDefaultsKey)
        let restore = try Fixtures.makeReadOnly(dir)

        let failed = WatchSyncStateStore(directory: dir, legacyDefaults: defaults)
        #expect(failed.transportEligibleEntries().isEmpty)
        #expect(failed.routineChallengeContext.isEmpty)
        #expect(defaults.data(forKey: WatchSyncStateStore.legacyDefaultsKey) != nil)

        restore()
        let recovered = WatchSyncStateStore(directory: dir, legacyDefaults: defaults)
        #expect(recovered.all.count == 1)
        #expect(recovered.all[0].templateTransaction != nil)
        #expect(recovered.transportEligibleEntries().count == 1)
        #expect(defaults.data(forKey: WatchSyncStateStore.legacyDefaultsKey) == nil)
    }

    @Test
    func exhaustedRoutineSequenceRotatesSenderEpochInsteadOfTrapping() throws {
        let dir = try Fixtures.makeTempDirectory()
        _ = WatchSyncStateStore(directory: dir, legacyDefaults: nil)
        let routineID = UUID()
        let oldEpoch = UUID()
        let stateURL = dir.appendingPathComponent("outgoing-queue.json")
        let data = try Data(contentsOf: stateURL)
        var state = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        state["senderEpoch"] = oldEpoch.uuidString
        state["nextSequenceByRoutine"] = [routineID.uuidString: NSNumber(value: UInt64.max)]
        try JSONSerialization.data(withJSONObject: state).write(to: stateURL, options: .atomic)

        let reloaded = WatchSyncStateStore(directory: dir, legacyDefaults: nil)
        let workout = Fixtures.makeWorkout(routineId: routineID, shouldUpdateTemplate: true)
        try reloaded.enqueue(workout, phase: .transportEligible)

        let transaction = try #require(
            Fixtures.templateEntry(in: reloaded, forWorkout: workout.id)?.templateTransaction
        )
        #expect(transaction.sequence == 0)
        #expect(transaction.senderEpoch != oldEpoch)
    }

    // MARK: - Ordering gate

    @Test
    func onlyTheHeadTransactionPerRoutineIsTransportEligible() throws {
        let store = WatchSyncStateStore(directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil)
        let routineA = UUID()
        let routineB = UUID()
        let a0Workout = Fixtures.makeWorkout(routineId: routineA, shouldUpdateTemplate: true)
        let a1Workout = Fixtures.makeWorkout(routineId: routineA, shouldUpdateTemplate: true)
        let b0Workout = Fixtures.makeWorkout(routineId: routineB, shouldUpdateTemplate: true)
        // A no-template workout is independent — it cannot mutate a routine.
        let plainWorkout = Fixtures.makeWorkout(routineId: routineA)

        try store.enqueue(a0Workout, phase: .transportEligible)
        try store.enqueue(a1Workout, phase: .transportEligible)
        try store.enqueue(b0Workout, phase: .transportEligible)
        try store.enqueue(plainWorkout, phase: .transportEligible)
        let a0 = try #require(Fixtures.templateEntry(in: store, forWorkout: a0Workout.id))
        let a1 = try #require(Fixtures.templateEntry(in: store, forWorkout: a1Workout.id))
        let b0 = try #require(Fixtures.templateEntry(in: store, forWorkout: b0Workout.id))

        // Every workout's history is eligible immediately, whatever its
        // routine's transaction queue is doing.
        let eligible = store.transportEligibleEntries()
        #expect(Set(eligible.compactMap(\.workoutID))
            == [a0Workout.id, a1Workout.id, b0Workout.id, plainWorkout.id])
        // Only the head transaction per routine.
        #expect(Set(eligible.filter(\.hasTemplateIntent).map(\.id)) == [a0.id, b0.id])

        // Retiring the head releases exactly the next transaction.
        store.retire(id: a0.id)
        #expect(store.transportEligibleEntries().contains { $0.id == a1.id })
    }

    @Test
    func failedRetirementDoesNotReleaseTheNextRoutineTransaction() throws {
        let dir = try Fixtures.makeTempDirectory()
        let store = WatchSyncStateStore(directory: dir, legacyDefaults: nil)
        let routineID = UUID()
        let firstWorkout = Fixtures.makeWorkout(routineId: routineID, shouldUpdateTemplate: true)
        let secondWorkout = Fixtures.makeWorkout(routineId: routineID, shouldUpdateTemplate: true)
        try store.enqueue(firstWorkout, phase: .transportEligible)
        try store.enqueue(secondWorkout, phase: .transportEligible)
        let first = try #require(Fixtures.templateEntry(in: store, forWorkout: firstWorkout.id))
        let second = try #require(Fixtures.templateEntry(in: store, forWorkout: secondWorkout.id))
        let restore = try Fixtures.makeReadOnly(dir)

        store.retire(id: first.id)
        #expect(pendingTemplateEntries(store).count == 2)
        #expect(store.transportEligibleEntries().filter(\.hasTemplateIntent).map(\.id) == [first.id])

        restore()
        store.retire(id: first.id)
        #expect(store.transportEligibleEntries().filter(\.hasTemplateIntent).map(\.id) == [second.id])
    }

    /// A quarantined entry is terminal: its exact bytes can never transport and
    /// no acknowledgment will ever retire it. Letting it keep the per-routine
    /// FIFO head would therefore block every later transaction for that routine
    /// permanently — including a completed workout carrying real history.
    @Test
    func aQuarantinedPredecessorDoesNotBlockTheNextRoutineTransaction() throws {
        let store = WatchSyncStateStore(directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil)
        let routineID = UUID()
        let doomedWorkout = Fixtures.makeWorkout(routineId: routineID, shouldUpdateTemplate: true)
        let laterWorkout = Fixtures.makeWorkout(routineId: routineID, shouldUpdateTemplate: true)
        try store.enqueue(doomedWorkout, phase: .transportEligible)
        try store.enqueue(laterWorkout, phase: .transportEligible)
        let doomed = try #require(Fixtures.templateEntry(in: store, forWorkout: doomedWorkout.id))
        let later = try #require(Fixtures.templateEntry(in: store, forWorkout: laterWorkout.id))
        #expect(store.transportEligibleEntries().filter(\.hasTemplateIntent).map(\.id) == [doomed.id])

        store.quarantine(id: doomed.id, reason: "payload permanently untransportable")

        #expect(store.transportEligibleEntries().filter(\.hasTemplateIntent).map(\.id) == [later.id])
    }

    // MARK: - Acknowledgment + routine context convergence

    /// Establishes an authoritative base on a fresh store. An unknown epoch is
    /// only ever accepted as a receiver-authorized handover, so this mirrors
    /// what the iOS authority actually sends on bootstrap.
    @discardableResult
    private func bootstrap(
        _ store: WatchSyncStateStore,
        routines: [WatchRoutine],
        epoch: UUID,
        generation: UInt64 = 1
    ) -> Bool {
        let challenge = store.routineChallengeContext
        return store.applyRoutineContext(routines, header: RoutineSnapshotHeader(
            epoch: epoch,
            generation: generation,
            targetWatchInstanceID: UUID(uuidString: challenge[WatchRoutineSync.challengeWatchInstanceIDKey]!),
            fromEpoch: store.acceptedRoutineEpoch,
            handoverNonce: UUID(uuidString: challenge[WatchRoutineSync.challengeNonceKey]!)
        ))
    }

    /// Builds a store holding one pending template transaction whose routine
    /// base was established at `generation`. Returns the TEMPLATE half of the
    /// enqueue plus the workout it was accepted in (the folds below need the
    /// workout, which the template entry wraps rather than owns).
    private func makeStoreWithPendingTransaction(
        directory: URL,
        routine: WatchRoutine,
        epoch: UUID,
        generation: UInt64 = 1,
        actualWeight: Double = 80
    ) throws -> (store: WatchSyncStateStore, entry: OutgoingSyncEntry, workout: CompletedWatchWorkout) {
        let store = WatchSyncStateStore(directory: directory, legacyDefaults: nil)
        bootstrap(store, routines: [routine], epoch: epoch, generation: generation)
        let setId = routine.exercises[0].sets[0].id
        let workout = Fixtures.makeWorkout(
            routineId: routine.id,
            shouldUpdateTemplate: true,
            exercises: [Fixtures.makeExercise(
                id: routine.exercises[0].id,
                sets: [Fixtures.makeSet(id: setId, plannedReps: 10, actualReps: 12, plannedWeight: 60, actualWeight: actualWeight)]
            )]
        )
        try store.enqueue(workout, phase: .transportEligible, routineAnchor: routine)
        let entry = try #require(Fixtures.templateEntry(in: store, forWorkout: workout.id))
        return (store, entry, workout)
    }

    private func ack(for entry: OutgoingSyncEntry, routineEpoch: UUID, generation: UInt64) -> TemplateAckRecord {
        TemplateAckRecord(
            transactionID: entry.templateTransaction!.transactionID,
            outcomeRaw: TemplateTransactionOutcome.applied.rawValue,
            senderEpoch: entry.templateTransaction!.senderEpoch,
            sequence: entry.templateTransaction!.sequence,
            routineEpoch: routineEpoch,
            routineGeneration: generation
        )
    }

    @Test
    func pendingTransactionIsFoldedOverTheBaseUntilAckAndContextBothArrive() throws {
        let routine = Fixtures.makeWatchRoutine()
        let epoch = UUID()
        let (store, entry, workout) = try makeStoreWithPendingTransaction(
            directory: try Fixtures.makeTempDirectory(), routine: routine, epoch: epoch
        )

        // Optimistic value is visible immediately.
        #expect(store.effectiveRoutines()[0].exercises[0].sets[0].weight == 80)

        // An ordinary newer context that predates the update cannot erase it.
        store.applyRoutineContext([routine], header: RoutineSnapshotHeader(
            epoch: epoch, generation: 2, targetWatchInstanceID: nil, fromEpoch: nil, handoverNonce: nil
        ))
        #expect(store.effectiveRoutines()[0].exercises[0].sets[0].weight == 80)
        #expect(pendingTemplateEntries(store).count == 1)

        // Ack arrives first, naming generation 3: held until that applies.
        store.acknowledgeTemplateTransaction(ack(for: entry, routineEpoch: epoch, generation: 3))
        #expect(pendingTemplateEntries(store).count == 1)

        // The correlated context applies → the head retires and the base wins.
        let applied = WatchRoutineTemplateFold.apply(workout, to: routine)
        store.applyRoutineContext([applied], header: RoutineSnapshotHeader(
            epoch: epoch, generation: 3, targetWatchInstanceID: nil, fromEpoch: nil, handoverNonce: nil
        ))
        #expect(pendingTemplateEntries(store).isEmpty)
        #expect(store.effectiveRoutines()[0].exercises[0].sets[0].weight == 80)
    }

    @Test
    func effectiveRoutineObserverPublishesTemplateUpdateWithoutRelaunch() throws {
        let routine = Fixtures.makeWatchRoutine()
        let epoch = UUID()
        let store = WatchSyncStateStore(
            directory: try Fixtures.makeTempDirectory(),
            legacyDefaults: nil
        )
        bootstrap(store, routines: [routine], epoch: epoch)

        var publishedWeights: [Double] = []
        store.onEffectiveRoutinesChanged = {
            if let weight = store.effectiveRoutines().first?
                .exercises.first?.sets.first?.weight {
                publishedWeights.append(weight)
            }
        }

        let setID = routine.exercises[0].sets[0].id
        let workout = Fixtures.makeWorkout(
            routineId: routine.id,
            shouldUpdateTemplate: true,
            exercises: [Fixtures.makeExercise(
                id: routine.exercises[0].id,
                sets: [Fixtures.makeSet(
                    id: setID,
                    plannedReps: 10,
                    actualReps: 12,
                    plannedWeight: 60,
                    actualWeight: 80
                )]
            )]
        )

        try store.enqueue(
            workout,
            phase: .transportEligible,
            routineAnchor: routine
        )
        let entry = try #require(Fixtures.templateEntry(in: store, forWorkout: workout.id))

        // The already-running watch process must publish the optimistic fold
        // immediately; relaunching from the durable state file is not part of
        // the update path. The split enqueue publishes once for the whole
        // commit, not once per entry.
        #expect(publishedWeights == [80])

        let authoritative = WatchRoutineTemplateFold.apply(workout, to: routine)
        store.acknowledgeTemplateTransaction(
            ack(for: entry, routineEpoch: epoch, generation: 2)
        )
        store.applyRoutineContext([authoritative], header: RoutineSnapshotHeader(
            epoch: epoch,
            generation: 2,
            targetWatchInstanceID: nil,
            fromEpoch: nil,
            handoverNonce: nil
        ))

        #expect(pendingTemplateEntries(store).isEmpty)
        #expect(publishedWeights.last == 80)
        #expect(store.effectiveRoutines()[0].exercises[0].sets[0].weight == 80)
    }

    @Test
    func contextFirstThenAckConvergesIdentically() throws {
        let routine = Fixtures.makeWatchRoutine()
        let epoch = UUID()
        let (store, entry, workout) = try makeStoreWithPendingTransaction(
            directory: try Fixtures.makeTempDirectory(), routine: routine, epoch: epoch
        )

        let applied = WatchRoutineTemplateFold.apply(workout, to: routine)
        store.applyRoutineContext([applied], header: RoutineSnapshotHeader(
            epoch: epoch, generation: 3, targetWatchInstanceID: nil, fromEpoch: nil, handoverNonce: nil
        ))
        #expect(pendingTemplateEntries(store).count == 1)  // no ack yet

        store.acknowledgeTemplateTransaction(ack(for: entry, routineEpoch: epoch, generation: 3))
        #expect(pendingTemplateEntries(store).isEmpty)
        #expect(store.effectiveRoutines()[0].exercises[0].sets[0].weight == 80)
    }

    @Test
    func successorAckAndContextCannotRetirePastAnUnacknowledgedHead() throws {
        let routine = Fixtures.makeWatchRoutine()
        let epoch = UUID()
        let dir = try Fixtures.makeTempDirectory()
        let (store, first, firstWorkout) = try makeStoreWithPendingTransaction(
            directory: dir, routine: routine, epoch: epoch, actualWeight: 65
        )
        let secondWorkout = Fixtures.makeWorkout(
            routineId: routine.id,
            shouldUpdateTemplate: true,
            exercises: [Fixtures.makeExercise(
                id: routine.exercises[0].id,
                sets: [Fixtures.makeSet(
                    id: routine.exercises[0].sets[0].id,
                    plannedReps: 10, actualReps: 12,
                    plannedWeight: 60, actualWeight: 75
                )]
            )]
        )
        try store.enqueue(secondWorkout, phase: .transportEligible, routineAnchor: routine)
        let second = try #require(Fixtures.templateEntry(in: store, forWorkout: secondWorkout.id))
        let authoritative = WatchRoutineTemplateFold.apply(
            secondWorkout,
            to: WatchRoutineTemplateFold.apply(firstWorkout, to: routine)
        )

        // Models a migrated queue whose successor transfer was already in
        // flight and overtook the head across WatchConnectivity channels.
        store.acknowledgeTemplateTransaction(
            ack(for: second, routineEpoch: epoch, generation: 2)
        )
        store.applyRoutineContext([authoritative], header: RoutineSnapshotHeader(
            epoch: epoch, generation: 2,
            targetWatchInstanceID: nil, fromEpoch: nil, handoverNonce: nil
        ))

        #expect(pendingTemplateEntries(store).map(\.id) == [first.id, second.id])
        #expect(store.effectiveRoutines()[0].exercises[0].sets[0].weight == 75)

        // Once A is also satisfied, the per-routine satisfied prefix A,B can
        // retire together without ever exposing A over B.
        store.acknowledgeTemplateTransaction(
            ack(for: first, routineEpoch: epoch, generation: 2)
        )
        #expect(pendingTemplateEntries(store).isEmpty)
        #expect(store.effectiveRoutines()[0].exercises[0].sets[0].weight == 75)
    }

    @Test
    func heldAcknowledgmentSurvivesRelaunch() throws {
        let dir = try Fixtures.makeTempDirectory()
        let routine = Fixtures.makeWatchRoutine()
        let epoch = UUID()
        let (store, entry, _) = try makeStoreWithPendingTransaction(
            directory: dir, routine: routine, epoch: epoch
        )
        store.acknowledgeTemplateTransaction(ack(for: entry, routineEpoch: epoch, generation: 5))
        #expect(pendingTemplateEntries(store).count == 1)

        let reloaded = WatchSyncStateStore(directory: dir, legacyDefaults: nil)
        #expect(pendingTemplateEntries(reloaded).count == 1)
        // The context arrives after relaunch: the persisted ack still retires it.
        reloaded.applyRoutineContext([routine], header: RoutineSnapshotHeader(
            epoch: epoch, generation: 5, targetWatchInstanceID: nil, fromEpoch: nil, handoverNonce: nil
        ))
        #expect(pendingTemplateEntries(reloaded).isEmpty)
    }

    @Test
    func failedAcknowledgmentPersistenceCannotRetireOrReleaseWork() throws {
        let dir = try Fixtures.makeTempDirectory()
        let routine = Fixtures.makeWatchRoutine()
        let epoch = UUID()
        let (store, entry, _) = try makeStoreWithPendingTransaction(
            directory: dir, routine: routine, epoch: epoch
        )
        store.applyRoutineContext([routine], header: RoutineSnapshotHeader(
            epoch: epoch, generation: 3, targetWatchInstanceID: nil, fromEpoch: nil, handoverNonce: nil
        ))
        let terminalAck = ack(for: entry, routineEpoch: epoch, generation: 3)
        let restore = try Fixtures.makeReadOnly(dir)

        store.acknowledgeTemplateTransaction(terminalAck)
        #expect(pendingTemplateEntries(store).count == 1)
        #expect(pendingTemplateEntries(store)[0].heldAck == nil)

        restore()
        store.acknowledgeTemplateTransaction(terminalAck)
        #expect(pendingTemplateEntries(store).isEmpty)
    }

    /// A plain ack retires history — including the history half of a split
    /// template-carrying workout, which is an ordinary workout payload — but
    /// never a legacy fused entry, whose single payload still carries the
    /// user's template intent an old iOS build never processed.
    @Test
    func plainAckRetiresHistoryButNeverALegacyFusedTransaction() throws {
        let (defaults, suiteName) = Fixtures.makeDefaultsSuite()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let fused = Fixtures.makeWorkout(shouldUpdateTemplate: true)
        defaults.set(try JSONEncoder().encode([fused]), forKey: WatchSyncStateStore.legacyDefaultsKey)
        let store = WatchSyncStateStore(
            directory: try Fixtures.makeTempDirectory(), legacyDefaults: defaults
        )
        let split = Fixtures.makeWorkout(shouldUpdateTemplate: true)
        let plain = Fixtures.makeWorkout()
        try store.enqueue(split, phase: .transportEligible)
        try store.enqueue(plain, phase: .transportEligible)

        store.acknowledgePlain(workoutId: fused.id)
        store.acknowledgePlain(workoutId: split.id)
        store.acknowledgePlain(workoutId: plain.id)

        #expect(store.entry(id: fused.id)?.hasTemplateIntent == true)
        #expect(store.entry(id: split.id) == nil)
        // The split's template transaction is untouched by the workout's ack.
        #expect(Fixtures.templateEntry(in: store, forWorkout: split.id) != nil)
        #expect(store.entry(id: plain.id) == nil)
    }

    @Test
    func acknowledgmentWithMismatchedTransactionIDIsIgnored() throws {
        let routine = Fixtures.makeWatchRoutine()
        let epoch = UUID()
        let (store, entry, _) = try makeStoreWithPendingTransaction(
            directory: try Fixtures.makeTempDirectory(), routine: routine, epoch: epoch
        )
        var wrong = ack(for: entry, routineEpoch: epoch, generation: 3)
        wrong = TemplateAckRecord(
            transactionID: UUID(), outcomeRaw: wrong.outcomeRaw, senderEpoch: wrong.senderEpoch,
            sequence: wrong.sequence, routineEpoch: wrong.routineEpoch,
            routineGeneration: wrong.routineGeneration
        )
        store.acknowledgeTemplateTransaction(wrong)

        store.applyRoutineContext([routine], header: RoutineSnapshotHeader(
            epoch: epoch, generation: 3, targetWatchInstanceID: nil, fromEpoch: nil, handoverNonce: nil
        ))
        #expect(pendingTemplateEntries(store).count == 1)
    }

    @Test
    func acknowledgmentWithMismatchedEpochOrSequenceIsIgnored() throws {
        let routine = Fixtures.makeWatchRoutine()
        let epoch = UUID()
        let (store, entry, _) = try makeStoreWithPendingTransaction(
            directory: try Fixtures.makeTempDirectory(), routine: routine, epoch: epoch
        )
        let valid = ack(for: entry, routineEpoch: epoch, generation: 3)
        let malformed = TemplateAckRecord(
            transactionID: valid.transactionID,
            outcomeRaw: valid.outcomeRaw,
            senderEpoch: UUID(),
            sequence: valid.sequence + 1,
            routineEpoch: valid.routineEpoch,
            routineGeneration: valid.routineGeneration
        )
        store.applyRoutineContext([routine], header: RoutineSnapshotHeader(
            epoch: epoch, generation: 3, targetWatchInstanceID: nil, fromEpoch: nil, handoverNonce: nil
        ))
        store.acknowledgeTemplateTransaction(malformed)
        #expect(pendingTemplateEntries(store).count == 1)
    }

    @Test
    func unsupportedAcknowledgmentVersionIsNotParsed() {
        let payload: [String: Any] = [
            WatchRoutineSync.ackVersionKey: "999",
            WatchRoutineSync.ackTransactionIDKey: UUID().uuidString,
            WatchRoutineSync.ackOutcomeKey: TemplateTransactionOutcome.applied.rawValue,
            WatchRoutineSync.ackSenderEpochKey: UUID().uuidString,
            WatchRoutineSync.ackSequenceKey: "0",
            WatchRoutineSync.ackRoutineEpochKey: UUID().uuidString,
            WatchRoutineSync.ackRoutineGenerationKey: "1"
        ]
        #expect(TemplateAckRecord.from(payload: payload) == nil)
    }

    // MARK: - Routine authority (receiver rules)

    @Test
    func staleRetiredAndUnauthorizedRoutineContextsCannotReplaceTheBase() throws {
        let store = WatchSyncStateStore(directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil)
        let routine = Fixtures.makeWatchRoutine(name: "Base")
        let other = Fixtures.makeWatchRoutine(id: routine.id, name: "Replaced")
        let epoch = UUID()

        #expect(bootstrap(store, routines: [routine], epoch: epoch, generation: 5))
        // Lower generation within the same epoch loses.
        #expect(!store.applyRoutineContext([other], header: RoutineSnapshotHeader(
            epoch: epoch, generation: 4, targetWatchInstanceID: nil, fromEpoch: nil, handoverNonce: nil
        )))
        // Equal generation is an idempotent redelivery, not a replacement.
        #expect(!store.applyRoutineContext([other], header: RoutineSnapshotHeader(
            epoch: epoch, generation: 5, targetWatchInstanceID: nil, fromEpoch: nil, handoverNonce: nil
        )))
        // An unknown epoch without a valid handover is rejected outright.
        #expect(!store.applyRoutineContext([other], header: RoutineSnapshotHeader(
            epoch: UUID(), generation: 99, targetWatchInstanceID: nil, fromEpoch: nil, handoverNonce: nil
        )))
        #expect(store.effectiveRoutines()[0].name == "Base")
    }

    @Test
    func handoverIsAcceptedOnlyForTheExactChallengeAndRetiresThePreviousEpoch() throws {
        let store = WatchSyncStateStore(directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil)
        let routine = Fixtures.makeWatchRoutine(name: "Base")
        let firstEpoch = UUID()
        bootstrap(store, routines: [routine], epoch: firstEpoch)

        let challenge = store.routineChallengeContext
        let instanceID = UUID(uuidString: challenge[WatchRoutineSync.challengeWatchInstanceIDKey]!)!
        let nonce = UUID(uuidString: challenge[WatchRoutineSync.challengeNonceKey]!)!
        let newEpoch = UUID()
        let handedOver = Fixtures.makeWatchRoutine(id: routine.id, name: "Handover")

        // Wrong nonce is refused.
        #expect(!store.applyRoutineContext([handedOver], header: RoutineSnapshotHeader(
            epoch: newEpoch, generation: 1, targetWatchInstanceID: instanceID,
            fromEpoch: firstEpoch, handoverNonce: UUID()
        )))
        // Exact target + from-epoch + unused nonce is accepted.
        #expect(store.applyRoutineContext([handedOver], header: RoutineSnapshotHeader(
            epoch: newEpoch, generation: 1, targetWatchInstanceID: instanceID,
            fromEpoch: firstEpoch, handoverNonce: nonce
        )))
        #expect(store.effectiveRoutines()[0].name == "Handover")
        #expect(store.acceptedRoutineEpoch == newEpoch)

        // The nonce was consumed and the old epoch retired forever.
        let rotated = store.routineChallengeContext[WatchRoutineSync.challengeNonceKey]
        #expect(rotated != nonce.uuidString)
        #expect(!store.applyRoutineContext([routine], header: RoutineSnapshotHeader(
            epoch: firstEpoch, generation: 99, targetWatchInstanceID: nil, fromEpoch: nil, handoverNonce: nil
        )))
    }

    @Test
    func legacyRoutineCacheBecomesTheInitialBaseAndUnversionedContextsStillUpdateIt() throws {
        let (defaults, suiteName) = Fixtures.makeDefaultsSuite()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cached = Fixtures.makeWatchRoutine(name: "Cached")
        defaults.set(try JSONEncoder().encode([cached]), forKey: WatchSyncStateStore.legacyRoutinesKey)

        let store = WatchSyncStateStore(directory: try Fixtures.makeTempDirectory(), legacyDefaults: defaults)
        #expect(store.effectiveRoutines().map(\.name) == ["Cached"])

        // A legacy (unversioned) context updates the base without establishing
        // an authority — a pre-ticket-05 iOS build behaves exactly as before.
        store.applyRoutineContext([Fixtures.makeWatchRoutine(id: cached.id, name: "Legacy")], header: nil)
        #expect(store.effectiveRoutines().map(\.name) == ["Legacy"])
        #expect(store.acceptedRoutineEpoch == nil)
    }

    @Test
    func identicalUnversionedContextRefreshesAndPersistsSyncDate() async throws {
        let directory = try Fixtures.makeTempDirectory()
        let routine = Fixtures.makeWatchRoutine()
        let store = WatchSyncStateStore(directory: directory, legacyDefaults: nil)

        #expect(store.applyRoutineContext([routine], header: nil))
        let initialSyncDate = try #require(store.lastRoutineSyncDate)
        var refreshCount = 0
        store.onEffectiveRoutinesChanged = { refreshCount += 1 }

        try await Task.sleep(for: .milliseconds(20))
        #expect(!store.applyRoutineContext([routine], header: nil))

        let refreshedSyncDate = try #require(store.lastRoutineSyncDate)
        #expect(refreshedSyncDate > initialSyncDate)
        #expect(refreshCount == 1)

        let reloaded = WatchSyncStateStore(directory: directory, legacyDefaults: nil)
        #expect(reloaded.lastRoutineSyncDate == refreshedSyncDate)
        #expect(reloaded.effectiveRoutines() == [routine])
    }

    @Test
    func malformedVersionedRoutineHeadersCannotDowngradeToLegacy() {
        #expect(RoutineSnapshotHeader.parse(context: [:]) == .legacy)
        #expect(RoutineSnapshotHeader.parse(context: [
            WatchRoutineSync.contextEpochKey: UUID().uuidString
        ]) == .malformed)
        #expect(RoutineSnapshotHeader.parse(context: [
            WatchRoutineSync.contextGenerationKey: "1"
        ]) == .malformed)
        #expect(RoutineSnapshotHeader.parse(context: [
            WatchRoutineSync.contextEpochKey: "not-a-uuid",
            WatchRoutineSync.contextGenerationKey: "1"
        ]) == .malformed)
        #expect(RoutineSnapshotHeader.parse(context: [
            WatchRoutineSync.contextEpochKey: UUID().uuidString,
            WatchRoutineSync.contextGenerationKey: "1",
            WatchRoutineSync.contextHandoverNonceKey: "not-a-uuid"
        ]) == .malformed)
    }

    // MARK: - iOS routine authority (sender rules)

    @MainActor
    private final class RecordingRoutineTransport: RoutineContextTransporting {
        private(set) var sent: [[String: Any]] = []
        var failNext = false
        /// Stands in for WatchConnectivity's cached watch → iOS context, so a
        /// test can exercise challenge recovery without a delegate delivery.
        var receivedWatchContext: [String: Any] = [:]

        func sendRoutineContext(_ context: [String: Any]) throws {
            if failNext {
                failNext = false
                throw CocoaError(.fileWriteUnknown)
            }
            sent.append(context)
        }
    }

    private func challengeContext(from store: WatchSyncStateStore) -> [String: Any] {
        store.routineChallengeContext
    }

    @Test
    func senderSupportsLegacyWatchThenProposesAHandoverWhenChallengeArrives() throws {
        let transport = RecordingRoutineTransport()
        let authority = RoutineSyncAuthority(transport: transport, directory: try Fixtures.makeTempDirectory())
        let routines = [Fixtures.makeWatchRoutine()]

        // An old watch has no challenge but still needs the legacy routines.
        #expect(authority.sendOrdinary(routines) == nil)
        #expect(transport.sent.count == 1)
        #expect(transport.sent[0][WatchRoutineSync.contextEpochKey] == nil)

        let watch = WatchSyncStateStore(directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil)
        authority.updateChallenge(fromApplicationContext: challengeContext(from: watch))

        let staged = try #require(authority.sendAuthoritative(routines))
        #expect(staged.generation == 1)
        let sent = transport.sent[1]
        #expect(sent[WatchRoutineSync.contextHandoverNonceKey] != nil)
        #expect(sent[WatchRoutineSync.contextTargetWatchInstanceIDKey] != nil)

        // The watch accepts that proposal, then republishes it as its epoch.
        let header = try #require(RoutineSnapshotHeader.from(context: sent))
        #expect(watch.applyRoutineContext(routines, header: header))
        authority.updateChallenge(fromApplicationContext: challengeContext(from: watch))

        // Subsequent sends stay in the accepted epoch with higher generations.
        let next = try #require(authority.sendAuthoritative(routines))
        #expect(next.epoch == staged.epoch)
        #expect(next.generation > staged.generation)
    }

    /// Regression: `WCSession.activate()` is asynchronous, so the composition
    /// root's launch drain runs before `activationDidCompleteWith` — which used
    /// to be the only place the cached watch context was read. A template
    /// transaction committed in that window could not stage an authoritative
    /// snapshot, parked at `committedAwaitingContext`, never sent its terminal
    /// acknowledgment, and so pinned the watch's per-routine FIFO head forever;
    /// every later workout for that routine was silently never transmitted.
    @Test
    func authorityStagesFromTheCachedContextWhenNoDeliveryHasHappenedYet() throws {
        let transport = RecordingRoutineTransport()
        let watch = WatchSyncStateStore(directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil)
        // WatchConnectivity holds the watch's challenge, but this process has
        // received no delegate callback and has no persisted state.
        transport.receivedWatchContext = challengeContext(from: watch)
        let authority = RoutineSyncAuthority(transport: transport, directory: try Fixtures.makeTempDirectory())

        let staged = try #require(
            authority.sendAuthoritative([Fixtures.makeWatchRoutine()]),
            "the cached application context must be enough to stage an authority"
        )
        #expect(staged.generation == 1)
        #expect(authority.publishedChallenge != nil)
    }

    /// Second layer of the same fix: once any process has seen the challenge it
    /// is persisted, so a later launch can stage even before WatchConnectivity
    /// reports anything at all.
    @Test
    func authorityRestoresThePersistedChallengeInANewProcess() throws {
        let directory = try Fixtures.makeTempDirectory()
        let watch = WatchSyncStateStore(directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil)

        let first = RoutineSyncAuthority(transport: RecordingRoutineTransport(), directory: directory)
        first.updateChallenge(fromApplicationContext: challengeContext(from: watch))

        // A fresh process: no delegate delivery, and WatchConnectivity reports
        // nothing cached either.
        let transport = RecordingRoutineTransport()
        let restored = RoutineSyncAuthority(transport: transport, directory: directory)
        #expect(restored.publishedChallenge != nil)
        #expect(restored.sendAuthoritative([Fixtures.makeWatchRoutine()]) != nil)
        #expect(transport.sent.count == 1)
    }

    @Test
    func identicalOrdinarySyncsAreSuppressedButAuthoritativeOnesAreNot() throws {
        let transport = RecordingRoutineTransport()
        let authority = RoutineSyncAuthority(transport: transport, directory: try Fixtures.makeTempDirectory())
        let watch = WatchSyncStateStore(directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil)
        authority.updateChallenge(fromApplicationContext: challengeContext(from: watch))
        let routines = [Fixtures.makeWatchRoutine()]

        #expect(authority.sendOrdinary(routines) != nil)
        #expect(authority.sendOrdinary(routines) == nil)   // identical bytes
        #expect(transport.sent.count == 1)

        // A rejected transaction leaves the routine bytes unchanged but still
        // needs a correlated generation, so this is never suppressed.
        #expect(authority.sendAuthoritative(routines) != nil)
        #expect(transport.sent.count == 2)
    }

    @Test
    func senderAdvancesPastAWatchThatIsAheadAndNeverReusesAGenerationOnFailure() throws {
        let transport = RecordingRoutineTransport()
        let dir = try Fixtures.makeTempDirectory()
        let authority = RoutineSyncAuthority(transport: transport, directory: dir)
        let watch = WatchSyncStateStore(directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil)
        authority.updateChallenge(fromApplicationContext: challengeContext(from: watch))
        let routines = [Fixtures.makeWatchRoutine()]

        let proposal = try #require(authority.sendOrdinary(routines))
        let header = try #require(RoutineSnapshotHeader.from(context: transport.sent[0]))
        watch.applyRoutineContext(routines, header: header)

        // The watch reports a much higher generation (restored iOS state):
        // the next snapshot must clear it rather than be rejected as stale.
        watch.applyRoutineContext(routines, header: RoutineSnapshotHeader(
            epoch: proposal.epoch, generation: 9,
            targetWatchInstanceID: nil, fromEpoch: nil, handoverNonce: nil
        ))
        authority.updateChallenge(fromApplicationContext: challengeContext(from: watch))
        let recovered = try #require(authority.sendAuthoritative(routines))
        #expect(recovered.epoch == proposal.epoch)
        #expect(recovered.generation == 10)

        // A send failure must not leave the consumed generation behind.
        transport.failNext = true
        #expect(authority.sendAuthoritative(routines) == nil)
        let afterFailure = try #require(authority.sendAuthoritative(routines))
        #expect(afterFailure.generation == 12)
    }

    @Test
    func senderUsesFreshHandoverInsteadOfOverflowingWatchGeneration() throws {
        let transport = RecordingRoutineTransport()
        let authority = RoutineSyncAuthority(transport: transport, directory: try Fixtures.makeTempDirectory())
        let watch = WatchSyncStateStore(directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil)
        authority.updateChallenge(fromApplicationContext: challengeContext(from: watch))
        let routines = [Fixtures.makeWatchRoutine()]

        let first = try #require(authority.sendAuthoritative(routines))
        let firstHeader = try #require(RoutineSnapshotHeader.from(context: transport.sent[0]))
        #expect(watch.applyRoutineContext(routines, header: firstHeader))
        watch.applyRoutineContext(routines, header: RoutineSnapshotHeader(
            epoch: first.epoch,
            generation: UInt64.max,
            targetWatchInstanceID: nil,
            fromEpoch: nil,
            handoverNonce: nil
        ))
        authority.updateChallenge(fromApplicationContext: challengeContext(from: watch))

        let recovered = try #require(authority.sendAuthoritative(routines))
        #expect(recovered.generation == 1)
        #expect(recovered.epoch != first.epoch)
        let header = try #require(RoutineSnapshotHeader.from(context: transport.sent.last!))
        #expect(header.targetWatchInstanceID != nil)
        #expect(header.fromEpoch == first.epoch)
    }

    @Test
    func authorityPersistenceFailureSendsNoUncommittedProposal() throws {
        let transport = RecordingRoutineTransport()
        let dir = try Fixtures.makeTempDirectory()
        let authority = RoutineSyncAuthority(transport: transport, directory: dir)
        let watch = WatchSyncStateStore(directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil)
        authority.updateChallenge(fromApplicationContext: challengeContext(from: watch))
        let restore = try Fixtures.makeReadOnly(dir)

        #expect(authority.sendAuthoritative([Fixtures.makeWatchRoutine()]) == nil)
        #expect(transport.sent.isEmpty)

        restore()
        #expect(authority.sendAuthoritative([Fixtures.makeWatchRoutine()]) != nil)
        #expect(transport.sent.count == 1)
    }
}
