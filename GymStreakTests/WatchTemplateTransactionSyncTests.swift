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

import Foundation
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct WatchTemplateTransactionSyncTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures

    // MARK: - Transaction identity

    @Test
    func templateEnqueueAllocatesStableIdentityAndPersistsIt() throws {
        let dir = try Fixtures.makeTempDirectory()
        let store = WatchSyncStateStore(directory: dir, legacyDefaults: nil)
        let routineId = UUID()

        let first = try store.enqueue(
            Fixtures.makeWorkout(routineId: routineId, shouldUpdateTemplate: true),
            phase: .transportEligible
        )
        let second = try store.enqueue(
            Fixtures.makeWorkout(routineId: routineId, shouldUpdateTemplate: true),
            phase: .transportEligible
        )

        #expect(first.templateTransaction?.transactionID != nil)
        #expect(first.templateTransaction?.sequence == 0)
        #expect(second.templateTransaction?.sequence == 1)
        // One persistent sender epoch is shared by every template transaction.
        #expect(first.templateTransaction?.senderEpoch == second.templateTransaction?.senderEpoch)

        // Identity survives relaunch, and the counter continues from the file.
        let reloaded = WatchSyncStateStore(directory: dir, legacyDefaults: nil)
        #expect(reloaded.entry(id: first.workoutID!)?.templateTransaction?.transactionID
            == first.templateTransaction?.transactionID)
        let third = try reloaded.enqueue(
            Fixtures.makeWorkout(routineId: routineId, shouldUpdateTemplate: true),
            phase: .transportEligible
        )
        #expect(third.templateTransaction?.sequence == 2)
        #expect(third.templateTransaction?.senderEpoch == first.templateTransaction?.senderEpoch)
    }

    @Test
    func sequencesAreAllocatedPerRoutineAndNoTemplateWorkoutsGetNoIdentity() throws {
        let store = WatchSyncStateStore(directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil)
        let routineA = UUID()
        let routineB = UUID()

        let a0 = try store.enqueue(Fixtures.makeWorkout(routineId: routineA, shouldUpdateTemplate: true), phase: .transportEligible)
        let b0 = try store.enqueue(Fixtures.makeWorkout(routineId: routineB, shouldUpdateTemplate: true), phase: .transportEligible)
        let plain = try store.enqueue(Fixtures.makeWorkout(routineId: routineA), phase: .transportEligible)

        #expect(a0.templateTransaction?.sequence == 0)
        #expect(b0.templateTransaction?.sequence == 0)
        #expect(plain.templateTransaction == nil)
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
        restore()

        // The failed attempt consumed no sequence: the next one still gets 0.
        let routineId = UUID()
        let entry = try store.enqueue(
            Fixtures.makeWorkout(routineId: routineId, shouldUpdateTemplate: true),
            phase: .transportEligible
        )
        #expect(entry.templateTransaction?.sequence == 0)
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
        let entry = try reloaded.enqueue(
            Fixtures.makeWorkout(routineId: routineID, shouldUpdateTemplate: true),
            phase: .transportEligible
        )

        #expect(entry.templateTransaction?.sequence == 0)
        #expect(entry.templateTransaction?.senderEpoch != oldEpoch)
    }

    // MARK: - Ordering gate

    @Test
    func onlyTheHeadTransactionPerRoutineIsTransportEligible() throws {
        let store = WatchSyncStateStore(directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil)
        let routineA = UUID()
        let routineB = UUID()

        let a0 = try store.enqueue(Fixtures.makeWorkout(routineId: routineA, shouldUpdateTemplate: true), phase: .transportEligible)
        let a1 = try store.enqueue(Fixtures.makeWorkout(routineId: routineA, shouldUpdateTemplate: true), phase: .transportEligible)
        let b0 = try store.enqueue(Fixtures.makeWorkout(routineId: routineB, shouldUpdateTemplate: true), phase: .transportEligible)
        // A no-template workout is independent — it cannot mutate a routine.
        let plain = try store.enqueue(Fixtures.makeWorkout(routineId: routineA), phase: .transportEligible)

        let eligible = Set(store.transportEligibleEntries().compactMap(\.workoutID))
        #expect(eligible == [a0.workoutID!, b0.workoutID!, plain.workoutID!])
        #expect(!eligible.contains(a1.workoutID!))

        // Retiring the head releases exactly the next transaction.
        store.retire(id: a0.id)
        #expect(store.transportEligibleEntries().contains { $0.id == a1.id })
    }

    @Test
    func failedRetirementDoesNotReleaseTheNextRoutineTransaction() throws {
        let dir = try Fixtures.makeTempDirectory()
        let store = WatchSyncStateStore(directory: dir, legacyDefaults: nil)
        let routineID = UUID()
        let first = try store.enqueue(
            Fixtures.makeWorkout(routineId: routineID, shouldUpdateTemplate: true), phase: .transportEligible
        )
        let second = try store.enqueue(
            Fixtures.makeWorkout(routineId: routineID, shouldUpdateTemplate: true), phase: .transportEligible
        )
        let restore = try Fixtures.makeReadOnly(dir)

        store.retire(id: first.id)
        #expect(store.all.count == 2)
        #expect(store.transportEligibleEntries().map(\.id) == [first.id])

        restore()
        store.retire(id: first.id)
        #expect(store.transportEligibleEntries().map(\.id) == [second.id])
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
    /// base was established at `generation`.
    private func makeStoreWithPendingTransaction(
        directory: URL,
        routine: WatchRoutine,
        epoch: UUID,
        generation: UInt64 = 1,
        actualWeight: Double = 80
    ) throws -> (store: WatchSyncStateStore, entry: OutgoingSyncEntry) {
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
        let entry = try store.enqueue(workout, phase: .transportEligible, routineAnchor: routine)
        return (store, entry)
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
        let (store, entry) = try makeStoreWithPendingTransaction(
            directory: try Fixtures.makeTempDirectory(), routine: routine, epoch: epoch
        )

        // Optimistic value is visible immediately.
        #expect(store.effectiveRoutines()[0].exercises[0].sets[0].weight == 80)

        // An ordinary newer context that predates the update cannot erase it.
        store.applyRoutineContext([routine], header: RoutineSnapshotHeader(
            epoch: epoch, generation: 2, targetWatchInstanceID: nil, fromEpoch: nil, handoverNonce: nil
        ))
        #expect(store.effectiveRoutines()[0].exercises[0].sets[0].weight == 80)
        #expect(store.all.count == 1)

        // Ack arrives first, naming generation 3: held until that applies.
        store.acknowledgeTemplateTransaction(ack(for: entry, routineEpoch: epoch, generation: 3))
        #expect(store.all.count == 1)

        // The correlated context applies → the head retires and the base wins.
        var applied = routine
        applied = WatchRoutineTemplateFold.apply(entry.completedWorkout!, to: routine)
        store.applyRoutineContext([applied], header: RoutineSnapshotHeader(
            epoch: epoch, generation: 3, targetWatchInstanceID: nil, fromEpoch: nil, handoverNonce: nil
        ))
        #expect(store.all.isEmpty)
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

        let entry = try store.enqueue(
            workout,
            phase: .transportEligible,
            routineAnchor: routine
        )

        // The already-running watch process must publish the optimistic fold
        // immediately; relaunching from the durable state file is not part of
        // the update path.
        #expect(publishedWeights == [80])

        let authoritative = WatchRoutineTemplateFold.apply(
            entry.completedWorkout!,
            to: routine
        )
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

        #expect(store.all.isEmpty)
        #expect(publishedWeights.last == 80)
        #expect(store.effectiveRoutines()[0].exercises[0].sets[0].weight == 80)
    }

    @Test
    func contextFirstThenAckConvergesIdentically() throws {
        let routine = Fixtures.makeWatchRoutine()
        let epoch = UUID()
        let (store, entry) = try makeStoreWithPendingTransaction(
            directory: try Fixtures.makeTempDirectory(), routine: routine, epoch: epoch
        )

        let applied = WatchRoutineTemplateFold.apply(entry.completedWorkout!, to: routine)
        store.applyRoutineContext([applied], header: RoutineSnapshotHeader(
            epoch: epoch, generation: 3, targetWatchInstanceID: nil, fromEpoch: nil, handoverNonce: nil
        ))
        #expect(store.all.count == 1)  // no ack yet

        store.acknowledgeTemplateTransaction(ack(for: entry, routineEpoch: epoch, generation: 3))
        #expect(store.all.isEmpty)
        #expect(store.effectiveRoutines()[0].exercises[0].sets[0].weight == 80)
    }

    @Test
    func successorAckAndContextCannotRetirePastAnUnacknowledgedHead() throws {
        let routine = Fixtures.makeWatchRoutine()
        let epoch = UUID()
        let dir = try Fixtures.makeTempDirectory()
        let (store, first) = try makeStoreWithPendingTransaction(
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
        let second = try store.enqueue(
            secondWorkout, phase: .transportEligible, routineAnchor: routine
        )
        let authoritative = WatchRoutineTemplateFold.apply(
            second.completedWorkout!,
            to: WatchRoutineTemplateFold.apply(first.completedWorkout!, to: routine)
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

        #expect(store.all.map(\.id) == [first.id, second.id])
        #expect(store.effectiveRoutines()[0].exercises[0].sets[0].weight == 75)

        // Once A is also satisfied, the per-routine satisfied prefix A,B can
        // retire together without ever exposing A over B.
        store.acknowledgeTemplateTransaction(
            ack(for: first, routineEpoch: epoch, generation: 2)
        )
        #expect(store.all.isEmpty)
        #expect(store.effectiveRoutines()[0].exercises[0].sets[0].weight == 75)
    }

    @Test
    func heldAcknowledgmentSurvivesRelaunch() throws {
        let dir = try Fixtures.makeTempDirectory()
        let routine = Fixtures.makeWatchRoutine()
        let epoch = UUID()
        let (store, entry) = try makeStoreWithPendingTransaction(
            directory: dir, routine: routine, epoch: epoch
        )
        store.acknowledgeTemplateTransaction(ack(for: entry, routineEpoch: epoch, generation: 5))
        #expect(store.all.count == 1)

        let reloaded = WatchSyncStateStore(directory: dir, legacyDefaults: nil)
        #expect(reloaded.all.count == 1)
        // The context arrives after relaunch: the persisted ack still retires it.
        reloaded.applyRoutineContext([routine], header: RoutineSnapshotHeader(
            epoch: epoch, generation: 5, targetWatchInstanceID: nil, fromEpoch: nil, handoverNonce: nil
        ))
        #expect(reloaded.all.isEmpty)
    }

    @Test
    func failedAcknowledgmentPersistenceCannotRetireOrReleaseWork() throws {
        let dir = try Fixtures.makeTempDirectory()
        let routine = Fixtures.makeWatchRoutine()
        let epoch = UUID()
        let (store, entry) = try makeStoreWithPendingTransaction(
            directory: dir, routine: routine, epoch: epoch
        )
        store.applyRoutineContext([routine], header: RoutineSnapshotHeader(
            epoch: epoch, generation: 3, targetWatchInstanceID: nil, fromEpoch: nil, handoverNonce: nil
        ))
        let terminalAck = ack(for: entry, routineEpoch: epoch, generation: 3)
        let restore = try Fixtures.makeReadOnly(dir)

        store.acknowledgeTemplateTransaction(terminalAck)
        #expect(store.all.count == 1)
        #expect(store.all[0].heldAck == nil)

        restore()
        store.acknowledgeTemplateTransaction(terminalAck)
        #expect(store.all.isEmpty)
    }

    @Test
    func plainAckNeverClearsTemplateIntentButClearsNoTemplateWorkouts() throws {
        let store = WatchSyncStateStore(directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil)
        let templateEntry = try store.enqueue(
            Fixtures.makeWorkout(shouldUpdateTemplate: true), phase: .transportEligible
        )
        let plainEntry = try store.enqueue(Fixtures.makeWorkout(), phase: .transportEligible)

        store.acknowledgePlain(workoutId: templateEntry.workoutID!)
        store.acknowledgePlain(workoutId: plainEntry.workoutID!)

        #expect(store.entry(id: templateEntry.id) != nil)
        #expect(store.entry(id: plainEntry.workoutID!) == nil)
    }

    @Test
    func acknowledgmentWithMismatchedTransactionIDIsIgnored() throws {
        let routine = Fixtures.makeWatchRoutine()
        let epoch = UUID()
        let (store, entry) = try makeStoreWithPendingTransaction(
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
        #expect(store.all.count == 1)
    }

    @Test
    func acknowledgmentWithMismatchedEpochOrSequenceIsIgnored() throws {
        let routine = Fixtures.makeWatchRoutine()
        let epoch = UUID()
        let (store, entry) = try makeStoreWithPendingTransaction(
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
        #expect(store.all.count == 1)
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
