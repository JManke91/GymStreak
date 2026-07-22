//
//  WatchWorkoutIngestionCoordinatorTests.swift
//  GymStreakTests
//
//  Covers the iOS receive pipeline end to end (ticket 04): isolated
//  no-template ingestion with receipt-before-ack ordering, duplicate and
//  lost-ack convergence (answered from receipts, even after history
//  deletion), save/receipt failure crash boundaries leaving everything
//  replayable and unacknowledged, no placeholder routines, idempotent
//  HealthKit placeholder replacement, and the untouched requested-template
//  path.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

// MARK: - Failing-save transaction fakes

@MainActor
private final class FailingSaveWorkoutSessionRepository: WorkoutSessionRepository {
    private let wrapped: WorkoutSessionRepository
    init(wrapping wrapped: WorkoutSessionRepository) { self.wrapped = wrapped }

    func fetchAll() -> [WorkoutSession] { wrapped.fetchAll() }
    func fetchCompleted() -> [WorkoutSession] { wrapped.fetchCompleted() }
    func findSession(id: UUID, healthKitWorkoutId: UUID?) -> WorkoutSession? {
        wrapped.findSession(id: id, healthKitWorkoutId: healthKitWorkoutId)
    }
    func insert(_ session: WorkoutSession) { wrapped.insert(session) }
    func delete(_ session: WorkoutSession) { wrapped.delete(session) }
    func insert(_ exercise: WorkoutExercise) { wrapped.insert(exercise) }
    func delete(_ exercise: WorkoutExercise) { wrapped.delete(exercise) }
    func insert(_ set: WorkoutSet) { wrapped.insert(set) }
    func delete(_ set: WorkoutSet) { wrapped.delete(set) }
    func save() throws { throw CocoaError(.fileWriteUnknown) }
}

@MainActor
private final class FailingSaveTransactionFactory: WorkoutHistoryTransacting {
    private let real: SwiftDataWorkoutHistoryTransactionFactory
    private(set) var rollbackCount = 0

    init(container: ModelContainer) {
        self.real = SwiftDataWorkoutHistoryTransactionFactory(container: container)
    }

    func makeIsolatedTransaction() -> WorkoutHistoryTransaction {
        FailingSaveTransaction(wrapping: real.makeIsolatedTransaction()) { [weak self] in
            self?.rollbackCount += 1
        }
    }
}

@MainActor
private final class FailingSaveTransaction: WorkoutHistoryTransaction {
    let routineRepository: RoutineRepository
    let workoutSessionRepository: WorkoutSessionRepository
    private let wrapped: WorkoutHistoryTransaction
    private let onRollback: () -> Void

    init(wrapping wrapped: WorkoutHistoryTransaction, onRollback: @escaping () -> Void) {
        self.wrapped = wrapped
        self.routineRepository = wrapped.routineRepository
        self.workoutSessionRepository = FailingSaveWorkoutSessionRepository(
            wrapping: wrapped.workoutSessionRepository
        )
        self.onRollback = onRollback
    }

    func rollback() {
        onRollback()
        wrapped.rollback()
    }
}

@MainActor
private final class FailingAuthoritativeRoutineSnapshotProvider: AuthoritativeRoutineSnapshotProviding {
    func fetchSnapshot() throws -> [WatchRoutine] {
        throw CocoaError(.fileReadUnknown)
    }
}

// MARK: - Tests

@Suite(.serialized)
@MainActor
struct WatchWorkoutIngestionCoordinatorTests {
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

        func deliver(_ workout: CompletedWatchWorkout) throws {
            if workout.shouldUpdateTemplate,
               workout.templateTransactionID != nil,
               workout.templateSenderEpoch != nil,
               workout.templateSequence != nil {
                let transaction = TemplateTransactionEnvelope(completedWorkout: workout)
                try inbox.store(
                    transactionData: try JSONEncoder().encode(transaction),
                    transactionID: transaction.transactionID
                )
            } else {
                try inbox.store(payloadData: try JSONEncoder().encode(workout), workoutId: workout.id)
            }
        }

        func sessions() -> [WorkoutSession] { sessionRepository.fetchAll() }

        /// Reads a routine's first set through a fresh context on the same
        /// container, matching the authoritative post-commit production read.
        func committedSet(routineId: UUID) throws -> (reps: Int, weight: Double) {
            let fresh = ModelContext(container)
            let routine = try #require(
                SwiftDataRoutineRepository(modelContext: fresh).fetch(id: routineId)
            )
            let set = try #require(routine.routineExercisesList.first?.setsList.first)
            return (set.reps, set.weight)
        }
    }

    private func makeHarness(
        transactionFactory: ((ModelContainer) -> WorkoutHistoryTransacting)? = nil,
        routineSnapshotProvider: ((ModelContainer) -> AuthoritativeRoutineSnapshotProviding)? = nil,
        receiptsDirectory: URL? = nil
    ) throws -> Harness {
        let container = InMemoryModelContainer.make()
        let context = container.mainContext
        let inbox = WatchWorkoutInboxStore(directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil)
        let receiptDirectory = try receiptsDirectory ?? Fixtures.makeTempDirectory()
        let receipts = WorkoutIngestReceiptStore(directory: receiptDirectory)
        let watchSync = MockWatchSyncServicing()
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let coordinator = WatchWorkoutIngestionCoordinator(
            inbox: inbox,
            receipts: receipts,
            historyTransactions: transactionFactory?(container)
                ?? SwiftDataWorkoutHistoryTransactionFactory(container: container),
            routineSnapshots: routineSnapshotProvider?(container)
                ?? SwiftDataAuthoritativeRoutineSnapshotProvider(container: container),
            routineSnapshotTransport: watchSync,
            mainContextCache: SwiftDataMainContextRoutineCacheRefresher(modelContext: context),
            watchSync: watchSync
        )
        return Harness(
            container: container, context: context, inbox: inbox, receipts: receipts,
            watchSync: watchSync, coordinator: coordinator,
            routineRepository: routineRepository, sessionRepository: sessionRepository
        )
    }

    private func makeWorkoutWithSets(shouldUpdateTemplate: Bool = false) -> CompletedWatchWorkout {
        Fixtures.makeWorkout(
            shouldUpdateTemplate: shouldUpdateTemplate,
            exercises: [Fixtures.makeExercise(sets: [Fixtures.makeSet()])]
        )
    }

    @Test
    func noTemplateIngestPersistsSessionThenReceiptThenRemovesInboxThenAcks() throws {
        let harness = try makeHarness()
        let workout = makeWorkoutWithSets()
        try harness.deliver(workout)

        harness.coordinator.drainInbox()

        let session = try #require(harness.sessions().first)
        #expect(session.id == workout.id)
        #expect(session.healthKitWorkoutId == workout.healthKitWorkoutId)
        #expect(session.workoutExercisesList.count == 1)
        #expect(harness.receipts.receipt(for: workout.id)?.phase == .readyToAcknowledgeNotRequested)
        #expect(harness.inbox.entries().isEmpty)
        #expect(harness.watchSync.acknowledgeWorkoutSavedCalls == [workout.id])
    }

    @Test
    func duplicatesAndLostAcksAreAnsweredFromReceiptWithoutReingestion() throws {
        let harness = try makeHarness()
        let workout = makeWorkoutWithSets()
        try harness.deliver(workout)
        harness.coordinator.drainInbox()

        // Lost-ack redelivery: answered from the receipt, no second session.
        try harness.deliver(workout)
        harness.coordinator.drainInbox()
        #expect(harness.sessions().count == 1)
        #expect(harness.watchSync.acknowledgeWorkoutSavedCalls == [workout.id, workout.id])

        // Even after the user deletes the history entry, the receipt keeps
        // the duplicate acknowledgment-only — nothing is resurrected.
        harness.sessionRepository.delete(harness.sessions()[0])
        try harness.sessionRepository.save()
        try harness.deliver(workout)
        harness.coordinator.drainInbox()
        #expect(harness.sessions().isEmpty)
        #expect(harness.inbox.entries().isEmpty)
        #expect(harness.watchSync.acknowledgeWorkoutSavedCalls.count == 3)
    }

    @Test
    func saveFailureRollsBackKeepsInboxAcksNothingAndRetryConverges() throws {
        var failingFactory: FailingSaveTransactionFactory?
        let harness = try makeHarness(transactionFactory: { container in
            let factory = FailingSaveTransactionFactory(container: container)
            failingFactory = factory
            return factory
        })
        let workout = makeWorkoutWithSets()
        try harness.deliver(workout)

        harness.coordinator.drainInbox()

        #expect(harness.sessions().isEmpty)
        #expect(failingFactory?.rollbackCount == 1)
        #expect(harness.inbox.entries().count == 1)
        #expect(harness.receipts.receipt(for: workout.id) == nil)
        #expect(harness.watchSync.acknowledgeWorkoutSavedCalls.isEmpty)

        // Retry with a working pipeline over the same durable stores: the
        // receipt is persisted before removal/ack and everything converges.
        let retry = WatchWorkoutIngestionCoordinator(
            inbox: harness.inbox,
            receipts: harness.receipts,
            historyTransactions: SwiftDataWorkoutHistoryTransactionFactory(container: harness.container),
            routineSnapshots: SwiftDataAuthoritativeRoutineSnapshotProvider(container: harness.container),
            routineSnapshotTransport: harness.watchSync,
            mainContextCache: SwiftDataMainContextRoutineCacheRefresher(modelContext: harness.context),
            watchSync: harness.watchSync
        )
        retry.drainInbox()

        #expect(harness.sessions().count == 1)
        #expect(harness.receipts.receipt(for: workout.id) != nil)
        #expect(harness.inbox.entries().isEmpty)
        #expect(harness.watchSync.acknowledgeWorkoutSavedCalls == [workout.id])
    }

    @Test
    func receiptWriteFailureKeepsInboxEntryAcksNothingThenConverges() throws {
        let receiptsDir = try Fixtures.makeTempDirectory()
        let container = InMemoryModelContainer.make()
        let context = container.mainContext
        let inbox = WatchWorkoutInboxStore(directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil)
        let receipts = WorkoutIngestReceiptStore(directory: receiptsDir)
        let watchSync = MockWatchSyncServicing()
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let coordinator = WatchWorkoutIngestionCoordinator(
            inbox: inbox,
            receipts: receipts,
            historyTransactions: SwiftDataWorkoutHistoryTransactionFactory(container: container),
            routineSnapshots: SwiftDataAuthoritativeRoutineSnapshotProvider(container: container),
            routineSnapshotTransport: watchSync,
            mainContextCache: SwiftDataMainContextRoutineCacheRefresher(modelContext: context),
            watchSync: watchSync
        )
        let workout = makeWorkoutWithSets()
        try inbox.store(payloadData: try JSONEncoder().encode(workout), workoutId: workout.id)

        let restore = try Fixtures.makeReadOnly(receiptsDir)
        coordinator.drainInbox()

        // History committed, but the receipt could not be persisted: the
        // entry stays replayable and nothing is acknowledged.
        #expect(sessionRepository.fetchAll().count == 1)
        #expect(inbox.entries().count == 1)
        #expect(watchSync.acknowledgeWorkoutSavedCalls.isEmpty)

        // Next drain (receipts writable again): dedupe finds the committed
        // session, persists the receipt first, then removes/acks — the
        // "history exists but receipt absent" migration case.
        restore()
        coordinator.drainInbox()
        #expect(sessionRepository.fetchAll().count == 1)
        #expect(receipts.receipt(for: workout.id) != nil)
        #expect(inbox.entries().isEmpty)
        #expect(watchSync.acknowledgeWorkoutSavedCalls == [workout.id])
    }

    @Test
    func missingRoutineProducesDenormalizedHistoryWithoutPlaceholderRoutine() throws {
        let harness = try makeHarness()
        let workout = makeWorkoutWithSets() // routineId matches nothing
        try harness.deliver(workout)

        harness.coordinator.drainInbox()

        let session = try #require(harness.sessions().first)
        #expect(session.routine == nil)
        #expect(session.routineName == workout.routineName)
        let routines = try harness.context.fetch(FetchDescriptor<Routine>())
        #expect(routines.isEmpty)
        #expect(harness.watchSync.acknowledgeWorkoutSavedCalls == [workout.id])
    }

    @Test
    func healthKitPlaceholderReplacementRemainsIdempotent() throws {
        let harness = try makeHarness()
        let workout = makeWorkoutWithSets()

        // A recovery-banner reconstruction: different session id, same
        // HealthKit external UUID, template values guessed as actuals.
        let placeholder = WorkoutSession(routine: nil)
        placeholder.routineName = workout.routineName
        placeholder.healthKitWorkoutId = workout.healthKitWorkoutId
        harness.sessionRepository.insert(placeholder)
        try harness.sessionRepository.save()

        try harness.deliver(workout)
        harness.coordinator.drainInbox()

        let sessions = harness.sessions()
        #expect(sessions.count == 1)
        #expect(sessions.first?.id == workout.id)

        // A redelivered duplicate stays acknowledgment-only.
        try harness.deliver(workout)
        harness.coordinator.drainInbox()
        #expect(harness.sessions().count == 1)
        #expect(harness.watchSync.acknowledgeWorkoutSavedCalls == [workout.id, workout.id])
    }

    // MARK: - Template transactions (ticket 05)

    /// Seeds a routine with one exercise and one set, and returns the ids a
    /// template-transaction payload must reference.
    @discardableResult
    private func seedRoutine(in harness: Harness) throws -> (routine: Routine, exercise: Exercise, routineExercise: RoutineExercise, set: ExerciseSet) {
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
        return (routine, exercise, routineExercise, set)
    }

    private func makeTransaction(
        seed: (routine: Routine, exercise: Exercise, routineExercise: RoutineExercise, set: ExerciseSet),
        senderEpoch: UUID,
        sequence: UInt64,
        actualReps: Int = 12,
        actualWeight: Double = 65,
        setId: UUID? = nil
    ) -> CompletedWatchWorkout {
        Fixtures.makeWorkout(
            routineId: seed.routine.id,
            shouldUpdateTemplate: true,
            exercises: [Fixtures.makeExercise(
                id: seed.routineExercise.id,
                exerciseId: seed.exercise.id,
                sets: [Fixtures.makeSet(
                    id: setId ?? seed.set.id,
                    plannedReps: 10, actualReps: actualReps,
                    plannedWeight: 60, actualWeight: actualWeight
                )]
            )],
            transactionID: UUID(),
            senderEpoch: senderEpoch,
            sequence: sequence
        )
    }

    @Test
    func templateTransactionCommitsHistoryAndTemplateThenStagesContextThenAcks() async throws {
        let harness = try makeHarness()
        let seed = try seedRoutine(in: harness)
        let workout = makeTransaction(seed: seed, senderEpoch: UUID(), sequence: 0)
        try harness.deliver(workout)

        harness.coordinator.drainInbox()

        #expect(harness.sessions().count == 1)
        #expect(harness.sessions().first?.didUpdateTemplate == true)
        let committed = try harness.committedSet(routineId: seed.routine.id)
        #expect(committed.reps == 12)
        #expect(committed.weight == 65)
        let mainContextRoutine = try #require(harness.routineRepository.fetch(id: seed.routine.id))
        let mainContextSet = try #require(mainContextRoutine.routineExercisesList.first?.setsList.first)
        #expect(mainContextSet.reps == 12)
        #expect(mainContextSet.weight == 65)

        // The authoritative snapshot is staged BEFORE the terminal ack, and
        // the receipt records the exact staged routine version.
        #expect(harness.watchSync.stageAuthoritativeRoutineSnapshotCalls.count == 1)
        let stagedRoutine = try #require(harness.watchSync.stageAuthoritativeRoutineSnapshotCalls.first?.first)
        let stagedSet = try #require(stagedRoutine.exercises.first?.sets.first)
        #expect(stagedSet.reps == 12)
        #expect(stagedSet.weight == 65)
        let receipt = try #require(harness.receipts.receipt(for: workout.id))
        #expect(receipt.phase == .readyToAcknowledge)
        #expect(receipt.outcome == .applied)

        let ack = try #require(harness.watchSync.templateAcks.first)
        #expect(ack.transactionID == workout.templateTransactionID)
        #expect(ack.outcome == .applied)
        #expect(ack.routineEpoch == receipt.routineEpoch)
        #expect(ack.routineGeneration == receipt.routineGeneration)
        #expect(harness.inbox.entries().isEmpty)
        // A template transaction is never answered with the plain ack.
        #expect(harness.watchSync.acknowledgeWorkoutSavedCalls.isEmpty)
    }

    @Test
    func authoritativeSnapshotFailureRetainsCommittedTransactionWithoutAcknowledging() async throws {
        let harness = try makeHarness(
            routineSnapshotProvider: { _ in FailingAuthoritativeRoutineSnapshotProvider() }
        )
        let seed = try seedRoutine(in: harness)
        let workout = makeTransaction(seed: seed, senderEpoch: UUID(), sequence: 0)
        try harness.deliver(workout)

        harness.coordinator.drainInbox()

        #expect(harness.sessions().count == 1)
        #expect(try harness.committedSet(routineId: seed.routine.id).weight == 65)
        #expect(harness.receipts.receipt(for: workout.id)?.phase == .committedAwaitingContext)
        #expect(harness.inbox.entries().count == 1)
        #expect(harness.watchSync.stageAuthoritativeRoutineSnapshotCalls.isEmpty)
        #expect(harness.watchSync.templateAcks.isEmpty)
    }

    @Test
    func dirtyMainContextIsPreservedWhileFreshAuthoritativeSnapshotUsesCommittedTemplate() async throws {
        let harness = try makeHarness()
        let seed = try seedRoutine(in: harness)
        seed.routine.name = "Unsaved iPhone Edit"
        #expect(harness.context.hasChanges)

        let workout = makeTransaction(seed: seed, senderEpoch: UUID(), sequence: 0)
        try harness.deliver(workout)
        harness.coordinator.drainInbox()

        #expect(harness.context.hasChanges)
        #expect(seed.routine.name == "Unsaved iPhone Edit")
        let committed = try harness.committedSet(routineId: seed.routine.id)
        #expect(committed.weight == 65)

        let stagedRoutine = try #require(
            harness.watchSync.stageAuthoritativeRoutineSnapshotCalls.first?.first
        )
        let stagedSet = try #require(stagedRoutine.exercises.first?.sets.first)
        #expect(stagedRoutine.name == "Push Day")
        #expect(stagedSet.weight == 65)
        #expect(harness.watchSync.templateAcks.count == 1)
    }

    @Test
    func receiptToSequenceFailureRepairsBeforeAcknowledgingOrReleasingSuccessor() async throws {
        let receiptsDirectory = try Fixtures.makeTempDirectory()
        let harness = try makeHarness(receiptsDirectory: receiptsDirectory)
        let seed = try seedRoutine(in: harness)
        let workout = makeTransaction(seed: seed, senderEpoch: UUID(), sequence: 0)
        try harness.deliver(workout)
        let sequenceDirectory = receiptsDirectory.appendingPathComponent("Sequences", isDirectory: true)
        let restore = try Fixtures.makeReadOnly(sequenceDirectory)

        harness.coordinator.drainInbox()

        #expect(harness.sessions().count == 1)
        #expect(try harness.committedSet(routineId: seed.routine.id).weight == 65)
        #expect(harness.inbox.entries().count == 1)
        #expect(harness.watchSync.templateAcks.isEmpty)

        restore()
        harness.coordinator.drainInbox()

        #expect(harness.receipts.nextExpectedSequence(
            for: workout.templateSenderEpoch!, routineID: workout.routineId
        ) == 1)
        #expect(harness.inbox.entries().isEmpty)
        #expect(harness.watchSync.templateAcks.count == 1)
    }

    @Test
    func sameSequenceReceiptWithDifferentTransactionIDIsRetainedAsInconsistent() throws {
        let harness = try makeHarness()
        let seed = try seedRoutine(in: harness)
        let workout = makeTransaction(seed: seed, senderEpoch: UUID(), sequence: 0)
        try harness.receipts.record(WorkoutIngestReceipt(
            workoutId: workout.id,
            healthKitWorkoutId: workout.healthKitWorkoutId,
            phase: .committedAwaitingContext,
            recordedAt: Date(),
            transactionID: UUID(),
            senderEpoch: workout.templateSenderEpoch,
            routineID: workout.routineId,
            sequence: workout.templateSequence,
            outcomeRaw: TemplateTransactionOutcome.applied.rawValue,
            protocolVersion: WatchRoutineSync.templateUpdateVersion
        ))
        try harness.deliver(workout)

        harness.coordinator.drainInbox()

        #expect(harness.sessions().isEmpty)
        #expect(harness.inbox.entries().count == 1)
        #expect(harness.watchSync.templateAcks.isEmpty)
    }

    @Test
    func lostPrimaryReceiptRecoveryDoesNotReapplyOldTemplateOverANewerEdit() async throws {
        let receiptsDirectory = try Fixtures.makeTempDirectory()
        let harness = try makeHarness(receiptsDirectory: receiptsDirectory)
        let seed = try seedRoutine(in: harness)
        let workout = makeTransaction(seed: seed, senderEpoch: UUID(), sequence: 0, actualWeight: 65)
        try harness.deliver(workout)
        let restore = try Fixtures.makeReadOnly(receiptsDirectory)

        harness.coordinator.drainInbox()

        #expect(harness.sessions().count == 1)
        #expect(try harness.committedSet(routineId: seed.routine.id).weight == 65)
        #expect(harness.inbox.entries().count == 1)
        #expect(harness.watchSync.templateAcks.isEmpty)

        restore()
        let routine = try #require(harness.routineRepository.fetch(id: seed.routine.id))
        let set = try #require(routine.routineExercisesList.first?.setsList.first)
        set.weight = 90
        try harness.routineRepository.save()

        harness.coordinator.drainInbox()

        #expect(try harness.committedSet(routineId: seed.routine.id).weight == 90)
        #expect(harness.inbox.entries().isEmpty)
        #expect(harness.watchSync.templateAcks.last?.outcome == .applied)
    }

    @Test
    func legacyHistoryFlagWithoutAtomicWitnessStillReconcilesTemplateAfterUpgrade() async throws {
        let harness = try makeHarness()
        let seed = try seedRoutine(in: harness)
        let workout = makeTransaction(seed: seed, senderEpoch: UUID(), sequence: 0, actualWeight: 65)

        // A pre-ticket-05 build could persist this flag even when its separate
        // template save failed. There is deliberately no atomic witness.
        let legacySession = WorkoutSession(routine: seed.routine)
        legacySession.id = workout.id
        legacySession.healthKitWorkoutId = workout.healthKitWorkoutId
        legacySession.didUpdateTemplate = true
        harness.sessionRepository.insert(legacySession)
        try harness.sessionRepository.save()
        try harness.deliver(workout)

        harness.coordinator.drainInbox()

        #expect(try harness.committedSet(routineId: seed.routine.id).weight == 65)
        let reconciled = try #require(harness.sessionRepository.findSession(
            id: workout.id, healthKitWorkoutId: workout.healthKitWorkoutId
        ))
        #expect(reconciled.watchTemplateTransactionID == workout.templateTransactionID)
        #expect(reconciled.watchTemplateOutcomeRaw == TemplateTransactionOutcome.applied.rawValue)
        #expect(harness.watchSync.templateAcks.last?.outcome == .applied)
    }

    @Test
    func delayedBackgroundDuplicateAfterNewerTransactionIsAcknowledgmentOnly() async throws {
        let harness = try makeHarness()
        let seed = try seedRoutine(in: harness)
        let epoch = UUID()
        let first = makeTransaction(seed: seed, senderEpoch: epoch, sequence: 0, actualWeight: 65)
        let second = makeTransaction(seed: seed, senderEpoch: epoch, sequence: 1, actualWeight: 75)

        try harness.deliver(first)       // A fast path
        harness.coordinator.drainInbox()
        try harness.deliver(second)      // B fast path
        harness.coordinator.drainInbox()
        try harness.deliver(first)       // delayed A background transfer
        harness.coordinator.drainInbox()

        #expect(harness.sessions().count == 2)
        #expect(try harness.committedSet(routineId: seed.routine.id).weight == 75)
        #expect(harness.watchSync.templateAcks.count == 3)
        #expect(harness.watchSync.templateAcks.last?.transactionID == first.templateTransactionID)
    }

    @Test
    func higherThanExpectedSequenceStaysBufferedUntilItsPredecessorArrives() async throws {
        let harness = try makeHarness()
        let seed = try seedRoutine(in: harness)
        let epoch = UUID()
        let a = makeTransaction(seed: seed, senderEpoch: epoch, sequence: 0, actualWeight: 65)
        let b = makeTransaction(seed: seed, senderEpoch: epoch, sequence: 1, actualWeight: 70)
        let c = makeTransaction(seed: seed, senderEpoch: epoch, sequence: 2, actualWeight: 75)

        // A establishes the ledger for this (epoch, routine).
        try harness.deliver(a)
        harness.coordinator.drainInbox()
        #expect(try harness.committedSet(routineId: seed.routine.id).weight == 65)

        // C overtakes B: above the expected sequence, so it stays durably
        // inboxed and mutates nothing.
        try harness.deliver(c)
        harness.coordinator.drainInbox()
        #expect(harness.sessions().count == 1)
        #expect(try harness.committedSet(routineId: seed.routine.id).weight == 65)
        #expect(harness.inbox.entries().count == 1)
        #expect(harness.watchSync.templateAcks.count == 1)

        // B arrives: B then the buffered C apply, in sequence order.
        try harness.deliver(b)
        harness.coordinator.drainInbox()
        #expect(harness.sessions().count == 3)
        #expect(try harness.committedSet(routineId: seed.routine.id).weight == 75)
        #expect(harness.inbox.entries().isEmpty)
        #expect(harness.watchSync.templateAcks.count == 3)
    }

    /// A brand-new ledger accepts whatever sequence it first sees. This is
    /// what keeps an iOS reinstall (receipts gone) from deadlocking against a
    /// watch that kept its epoch and per-routine counters.
    @Test
    func freshLedgerBootstrapsAtFirstObservedSequence() async throws {
        let harness = try makeHarness()
        let seed = try seedRoutine(in: harness)
        let workout = makeTransaction(seed: seed, senderEpoch: UUID(), sequence: 7)
        try harness.deliver(workout)

        harness.coordinator.drainInbox()

        #expect(try harness.committedSet(routineId: seed.routine.id).weight == 65)
        #expect(harness.watchSync.templateAcks.count == 1)
        #expect(harness.inbox.entries().isEmpty)
    }

    @Test
    func lowerThanExpectedWithoutReceiptIsSurfacedAndRetained() throws {
        let harness = try makeHarness()
        let seed = try seedRoutine(in: harness)
        let epoch = UUID()
        let stale = makeTransaction(seed: seed, senderEpoch: epoch, sequence: 0)
        try harness.receipts.advanceExpectedSequence(for: TemplateTransactionKey(
            senderEpoch: epoch, routineID: seed.routine.id, sequence: 0
        ))
        try harness.deliver(stale)

        harness.coordinator.drainInbox()

        #expect(harness.sessions().isEmpty)
        #expect(harness.inbox.entries().count == 1)
        #expect(harness.watchSync.templateAcks.isEmpty)
    }

    @Test
    func lateDuplicateOfTerminalTransactionIsAcknowledgmentOnly() async throws {
        let harness = try makeHarness()
        let seed = try seedRoutine(in: harness)
        let workout = makeTransaction(seed: seed, senderEpoch: UUID(), sequence: 0)
        try harness.deliver(workout)
        harness.coordinator.drainInbox()

        let stagedCalls = harness.watchSync.stageAuthoritativeRoutineSnapshotCalls.count

        // A delayed background copy of the same transaction arrives after its
        // outcome is terminal: answered from the receipt, no re-mutation.
        seed.set.weight = 80
        try harness.context.save()
        try harness.deliver(workout)
        harness.coordinator.drainInbox()

        #expect(harness.sessions().count == 1)
        #expect(seed.set.weight == 80)
        #expect(harness.watchSync.stageAuthoritativeRoutineSnapshotCalls.count == stagedCalls)
        #expect(harness.watchSync.templateAcks.count == 2)
        #expect(harness.watchSync.templateAcks[0].transactionID == harness.watchSync.templateAcks[1].transactionID)
        #expect(harness.inbox.entries().isEmpty)
    }

    @Test
    func malformedTemplateRequestRejectsWhollyWhileSavingHistory() async throws {
        let harness = try makeHarness()
        let seed = try seedRoutine(in: harness)
        // References a set id the routine does not have.
        let workout = makeTransaction(
            seed: seed, senderEpoch: UUID(), sequence: 0, setId: UUID()
        )
        try harness.deliver(workout)

        harness.coordinator.drainInbox()

        #expect(harness.sessions().count == 1)
        #expect(harness.sessions().first?.didUpdateTemplate == false)
        // The routine is left byte-for-byte untouched.
        let committed = try harness.committedSet(routineId: seed.routine.id)
        #expect(committed.reps == 10)
        #expect(committed.weight == 60)

        let ack = try #require(harness.watchSync.templateAcks.first)
        #expect(ack.outcome == .rejected)
        #expect(harness.receipts.receipt(for: workout.id)?.outcome == .rejected)
        #expect(harness.inbox.entries().isEmpty)
    }

    @Test
    func templateSaveFailureRollsBackAndAcknowledgesNothing() throws {
        var failingFactory: FailingSaveTransactionFactory?
        let harness = try makeHarness(transactionFactory: { container in
            let factory = FailingSaveTransactionFactory(container: container)
            failingFactory = factory
            return factory
        })
        let seed = try seedRoutine(in: harness)
        let workout = makeTransaction(seed: seed, senderEpoch: UUID(), sequence: 0)
        try harness.deliver(workout)

        harness.coordinator.drainInbox()

        #expect(harness.sessions().isEmpty)
        #expect(failingFactory?.rollbackCount == 1)
        #expect(harness.inbox.entries().count == 1)
        #expect(harness.receipts.receipt(for: workout.id) == nil)
        #expect(harness.watchSync.templateAcks.isEmpty)
        #expect(harness.watchSync.acknowledgeWorkoutSavedCalls.isEmpty)
    }

    @Test
    func withoutRoutineAuthorityTransactionStaysAwaitingContextThenCompletes() async throws {
        let harness = try makeHarness()
        harness.watchSync.stagedRoutineVersion = nil  // no watch challenge yet
        let seed = try seedRoutine(in: harness)
        let workout = makeTransaction(seed: seed, senderEpoch: UUID(), sequence: 0)
        try harness.deliver(workout)

        harness.coordinator.drainInbox()

        // The local commit is final, but no acknowledgment may be sent before
        // the authoritative routine state is staged.
        #expect(harness.sessions().count == 1)
        #expect(try harness.committedSet(routineId: seed.routine.id).weight == 65)
        #expect(harness.receipts.receipt(for: workout.id)?.phase == .committedAwaitingContext)
        #expect(harness.watchSync.templateAcks.isEmpty)
        #expect(harness.inbox.entries().count == 1)

        // The challenge arrives: the receipt resumes ONLY context staging and
        // acknowledgment — never a second mutation.
        harness.watchSync.stagedRoutineVersion = (UUID(), 4)
        harness.coordinator.drainInbox()

        #expect(harness.sessions().count == 1)
        #expect(harness.receipts.receipt(for: workout.id)?.phase == .readyToAcknowledge)
        #expect(harness.watchSync.templateAcks.count == 1)
        #expect(harness.watchSync.templateAcks[0].routineGeneration == 4)
        #expect(harness.inbox.entries().isEmpty)
    }

    @Test
    func rejectedAuthorityProposalRestagesReadyReceiptWithoutReapplyingMutation() async throws {
        let harness = try makeHarness()
        let firstVersion = (epoch: UUID(), generation: UInt64(3))
        harness.watchSync.stagedRoutineVersion = firstVersion
        let seed = try seedRoutine(in: harness)
        let workout = makeTransaction(seed: seed, senderEpoch: UUID(), sequence: 0)
        try harness.deliver(workout)
        harness.coordinator.drainInbox()

        #expect(harness.sessions().count == 1)
        #expect(harness.watchSync.templateAcks.count == 1)
        #expect(harness.inbox.entries().isEmpty)

        // A rotated challenge that did not accept the proposal requires a new
        // authoritative generation, even though the inbox entry is gone.
        harness.watchSync.watchRoutineChallenge = (UUID(), 0)
        let replacement = (epoch: UUID(), generation: UInt64(8))
        harness.watchSync.stagedRoutineVersion = replacement
        harness.coordinator.routineAuthorityDidChange()

        let key = TemplateTransactionKey(
            senderEpoch: workout.templateSenderEpoch!,
            routineID: workout.routineId,
            sequence: workout.templateSequence!
        )
        let receipt = try #require(harness.receipts.receipt(for: key))
        #expect(receipt.routineEpoch == replacement.epoch)
        #expect(receipt.routineGeneration == replacement.generation)
        #expect(harness.watchSync.stageAuthoritativeRoutineSnapshotCalls.count == 2)
        #expect(harness.watchSync.templateAcks.count == 2)
        #expect(harness.sessions().count == 1)
        #expect(try harness.committedSet(routineId: seed.routine.id).weight == 65)
    }

    @Test
    func appliedAuthorityVersionRetiresReceiptFromFutureRecoveryScans() async throws {
        let harness = try makeHarness()
        let accepted = (epoch: UUID(), generation: UInt64(3))
        harness.watchSync.stagedRoutineVersion = accepted
        let seed = try seedRoutine(in: harness)
        let workout = makeTransaction(seed: seed, senderEpoch: UUID(), sequence: 0)
        try harness.deliver(workout)
        harness.coordinator.drainInbox()

        #expect(harness.watchSync.stageAuthoritativeRoutineSnapshotCalls.count == 1)
        harness.watchSync.watchRoutineChallenge = accepted
        harness.coordinator.routineAuthorityDidChange()

        // Once the watch proves this generation applied, later challenges
        // must not rescan/restage an indefinitely retained dedupe receipt.
        harness.watchSync.watchRoutineChallenge = (UUID(), 0)
        harness.watchSync.stagedRoutineVersion = (UUID(), 8)
        harness.coordinator.routineAuthorityDidChange()

        #expect(harness.watchSync.stageAuthoritativeRoutineSnapshotCalls.count == 1)
        #expect(harness.sessions().count == 1)
        #expect(try harness.committedSet(routineId: seed.routine.id).weight == 65)
    }

    @Test
    func templateOnlyExecutorCommitsNoPlaceholderHistory() async throws {
        let harness = try makeHarness()
        let seed = try seedRoutine(in: harness)
        let transaction = SwiftDataWorkoutHistoryTransactionFactory(
            container: harness.container
        ).makeIsolatedTransaction()
        let routine = try #require(transaction.routineRepository.fetch(id: seed.routine.id))
        let set = try #require(routine.routineExercisesList.first?.setsList.first)
        let service = WatchTemplateTransactionService(
            routineRepository: transaction.routineRepository,
            workoutSessionRepository: transaction.workoutSessionRepository
        )

        let outcome = service.executeTemplateOnly(
            routineID: routine.id,
            updates: [.init(target: .routineSet(set), reps: 14, weight: 72.5)]
        )

        guard case .applied = outcome else {
            Issue.record("Expected template-only mutation to apply")
            return
        }
        #expect(transaction.workoutSessionRepository.fetchAll().isEmpty)
        #expect(try harness.committedSet(routineId: routine.id).reps == 14)
        #expect(try harness.committedSet(routineId: routine.id).weight == 72.5)
    }

    @Test
    func unsequencedLegacyPayloadReconcilesBeforeAuthorityAndIsRejectedAfter() async throws {
        let harness = try makeHarness()
        let seed = try seedRoutine(in: harness)

        // Old watch build: requested template update, no transaction identity.
        let legacy = Fixtures.makeWorkout(
            routineId: seed.routine.id,
            shouldUpdateTemplate: true,
            exercises: [Fixtures.makeExercise(
                id: seed.routineExercise.id,
                exerciseId: seed.exercise.id,
                sets: [Fixtures.makeSet(id: seed.set.id, plannedReps: 10, actualReps: 12, plannedWeight: 60, actualWeight: 65)]
            )]
        )
        try harness.deliver(legacy)
        harness.coordinator.drainInbox()

        // No sequenced authority exists yet → idempotent reconciliation runs,
        // answered with the plain ack an old watch understands.
        #expect(try harness.committedSet(routineId: seed.routine.id).weight == 65)
        #expect(harness.watchSync.acknowledgeWorkoutSavedCalls == [legacy.id])
        #expect(harness.watchSync.templateAcks.isEmpty)
        #expect(harness.sessionRepository.findSession(
            id: legacy.id, healthKitWorkoutId: legacy.healthKitWorkoutId
        )?.didUpdateTemplate == true)

        // Establish sequenced authority for this routine.
        let sequenced = makeTransaction(seed: seed, senderEpoch: UUID(), sequence: 0, actualWeight: 70)
        try harness.deliver(sequenced)
        harness.coordinator.drainInbox()
        let afterSequenced = try harness.committedSet(routineId: seed.routine.id)
        #expect(harness.watchSync.templateAcks.last?.outcome == .applied)
        #expect(afterSequenced.weight == 70)
        #expect(harness.watchSync.templateAcks.count == 1)
        #expect(harness.inbox.entries().isEmpty)

        // A second unsequenced legacy payload can no longer overwrite known
        // newer state: history is preserved, template intent is rejected.
        let stale = Fixtures.makeWorkout(
            routineId: seed.routine.id,
            shouldUpdateTemplate: true,
            exercises: [Fixtures.makeExercise(
                id: seed.routineExercise.id,
                exerciseId: seed.exercise.id,
                sets: [Fixtures.makeSet(id: seed.set.id, plannedReps: 10, actualReps: 8, plannedWeight: 60, actualWeight: 50)]
            )]
        )
        try harness.deliver(stale)
        harness.coordinator.drainInbox()

        #expect(try harness.committedSet(routineId: seed.routine.id).weight == 70)
        #expect(harness.sessions().count == 3)
        #expect(harness.watchSync.acknowledgeWorkoutSavedCalls == [legacy.id, stale.id])
        #expect(harness.sessionRepository.findSession(
            id: stale.id, healthKitWorkoutId: stale.healthKitWorkoutId
        )?.didUpdateTemplate == false)
        #expect(harness.watchSync.syncRoutineSnapshotCalls.count == 2)
    }
}
