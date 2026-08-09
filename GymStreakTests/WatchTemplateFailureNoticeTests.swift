//
//  WatchTemplateFailureNoticeTests.swift
//  GymStreakTests
//
//  Ticket 03 of the history/template split: a routine change the user accepted
//  on the watch that will NEVER be applied has to be told, and one that is
//  merely in flight has to stay silent.
//
//  Before the split (ADR 0001) a template update that could not be acknowledged
//  withheld the whole workout, which is loud. After it, the workout arrives and
//  only the routine update vanishes — so these tests pin the two terminal
//  outcomes that produce a notice (a `rejected` acknowledgment and a quarantined
//  payload), the reason each one reconstructs, and the silence everywhere else.
//
//  `WatchSyncStateStore` is an identical copy in both targets and there is no
//  watch unit-test target, so these stand in for it.
//

import Foundation
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct WatchTemplateFailureNoticeTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures

    // MARK: - Helpers

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

    /// A store with an authoritative base and one pending template transaction
    /// for `routine`, exactly as accepting "Save & update template" leaves it.
    private func makeStoreWithPendingTemplateIntent(
        directory: URL, routine: WatchRoutine, epoch: UUID
    ) throws -> (store: WatchSyncStateStore, template: OutgoingSyncEntry, workoutID: UUID) {
        let store = WatchSyncStateStore(directory: directory, legacyDefaults: nil)
        bootstrap(store, routines: [routine], epoch: epoch)
        let workout = Fixtures.makeWorkout(
            routineId: routine.id,
            routineName: routine.name,
            shouldUpdateTemplate: true,
            exercises: [Fixtures.makeExercise(
                id: routine.exercises[0].id,
                sets: [Fixtures.makeSet(
                    id: routine.exercises[0].sets[0].id, actualWeight: 80
                )]
            )]
        )
        try store.enqueue(workout, phase: .transportEligible, routineAnchor: routine)
        let template = try #require(Fixtures.templateEntry(in: store, forWorkout: workout.id))
        return (store, template, workout.id)
    }

    private func ack(
        for entry: OutgoingSyncEntry,
        outcome: TemplateTransactionOutcomeWire,
        routineEpoch: UUID,
        generation: UInt64
    ) -> TemplateAckRecord {
        let transaction = entry.templateTransaction!
        return TemplateAckRecord(
            transactionID: transaction.transactionID,
            outcomeRaw: outcome.rawValue,
            senderEpoch: transaction.senderEpoch,
            sequence: transaction.sequence,
            routineEpoch: routineEpoch,
            routineGeneration: generation
        )
    }

    // MARK: - Terminal rejection

    @Test
    func rejectedTemplateIntentProducesANoticeNamingTheRoutine() throws {
        let routine = Fixtures.makeWatchRoutine(name: "Push Day")
        let epoch = UUID()
        let (store, template, _) = try makeStoreWithPendingTemplateIntent(
            directory: try Fixtures.makeTempDirectory(), routine: routine, epoch: epoch
        )
        #expect(store.templateFailureNotices.isEmpty)

        store.acknowledgeTemplateTransaction(
            ack(for: template, outcome: .rejected, routineEpoch: epoch, generation: 2)
        )
        // The ack is held until its routine generation applies, so nothing is
        // terminal — and nothing is said — until the context arrives.
        #expect(store.templateFailureNotices.isEmpty)

        store.applyRoutineContext([routine], header: RoutineSnapshotHeader(
            epoch: epoch, generation: 2, targetWatchInstanceID: nil, fromEpoch: nil, handoverNonce: nil
        ))

        let notice = try #require(store.templateFailureNotices.first)
        #expect(store.templateFailureNotices.count == 1)
        #expect(notice.reason == .routineChangedOnPhone)
        #expect(notice.routineName == "Push Day")
        #expect(notice.routineID == routine.id)
        // The transaction itself is gone: the optimistic value reverted, which
        // is precisely what the notice explains.
        #expect(store.all.contains { $0.hasTemplateIntent } == false)
        #expect(store.effectiveRoutines()[0].exercises[0].sets[0].weight == 60)
    }

    @Test
    func rejectionForARoutineTheBaseNoLongerCarriesSaysItWasDeleted() throws {
        let routine = Fixtures.makeWatchRoutine(name: "Push Day")
        let epoch = UUID()
        let (store, template, _) = try makeStoreWithPendingTemplateIntent(
            directory: try Fixtures.makeTempDirectory(), routine: routine, epoch: epoch
        )

        store.acknowledgeTemplateTransaction(
            ack(for: template, outcome: .rejected, routineEpoch: epoch, generation: 2)
        )
        // The authoritative snapshot that comes with the rejection no longer
        // carries the routine at all — it was deleted on the iPhone.
        store.applyRoutineContext([], header: RoutineSnapshotHeader(
            epoch: epoch, generation: 2, targetWatchInstanceID: nil, fromEpoch: nil, handoverNonce: nil
        ))

        let notice = try #require(store.templateFailureNotices.first)
        #expect(notice.reason == .routineDeleted)
        #expect(notice.routineName == "Push Day")
    }

    @Test
    func appliedTemplateIntentSaysNothing() throws {
        let routine = Fixtures.makeWatchRoutine()
        let epoch = UUID()
        let (store, template, _) = try makeStoreWithPendingTemplateIntent(
            directory: try Fixtures.makeTempDirectory(), routine: routine, epoch: epoch
        )

        store.acknowledgeTemplateTransaction(
            ack(for: template, outcome: .applied, routineEpoch: epoch, generation: 2)
        )
        store.applyRoutineContext([routine], header: RoutineSnapshotHeader(
            epoch: epoch, generation: 2, targetWatchInstanceID: nil, fromEpoch: nil, handoverNonce: nil
        ))

        #expect(store.all.contains { $0.hasTemplateIntent } == false)
        #expect(store.templateFailureNotices.isEmpty)
    }

    // MARK: - Still in flight

    /// Pending is the normal state for every workout performed away from the
    /// phone, so it must produce no user-visible output at all — not after
    /// unrelated routine contexts, and not after a relaunch.
    @Test
    func templateIntentStillInFlightSaysNothingHoweverLongItStaysThere() throws {
        let routine = Fixtures.makeWatchRoutine()
        let epoch = UUID()
        let dir = try Fixtures.makeTempDirectory()
        let (store, _, _) = try makeStoreWithPendingTemplateIntent(
            directory: dir, routine: routine, epoch: epoch
        )

        for generation in UInt64(2)...6 {
            store.applyRoutineContext([routine], header: RoutineSnapshotHeader(
                epoch: epoch, generation: generation,
                targetWatchInstanceID: nil, fromEpoch: nil, handoverNonce: nil
            ))
        }
        #expect(store.templateFailureNotices.isEmpty)

        let relaunched = WatchSyncStateStore(directory: dir, legacyDefaults: nil)
        #expect(relaunched.all.contains { $0.hasTemplateIntent })
        #expect(relaunched.templateFailureNotices.isEmpty)
    }

    // MARK: - Quarantine

    @Test
    func quarantinedTemplateIntentProducesANoticeInNonTechnicalLanguage() throws {
        let routine = Fixtures.makeWatchRoutine(name: "Pull Day")
        let epoch = UUID()
        let (store, template, workoutID) = try makeStoreWithPendingTemplateIntent(
            directory: try Fixtures.makeTempDirectory(), routine: routine, epoch: epoch
        )

        store.quarantine(id: template.id, reason: "payloadTooLarge")

        let notice = try #require(store.templateFailureNotices.first)
        #expect(notice.reason == .couldNotSend)
        #expect(notice.routineName == "Pull Day")
        // The workout's own history entry is untouched and still transports —
        // the whole point of the split.
        #expect(store.transportEligibleEntries().map(\.workoutID) == [workoutID])
    }

    @Test
    func quarantinedHistoryEntryProducesNoTemplateNotice() throws {
        let store = WatchSyncStateStore(
            directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil
        )
        let workout = Fixtures.makeWorkout(shouldUpdateTemplate: false)
        try store.enqueue(workout, phase: .transportEligible)

        store.quarantine(id: workout.id, reason: "payloadTooLarge")

        // A lost workout is a different failure with a different escape hatch
        // (HealthKit recovery); this notice is only about template intent.
        #expect(store.templateFailureNotices.isEmpty)
    }

    @Test
    func aFailedQuarantineWriteRecordsNoNotice() throws {
        let routine = Fixtures.makeWatchRoutine()
        let dir = try Fixtures.makeTempDirectory()
        let (store, template, _) = try makeStoreWithPendingTemplateIntent(
            directory: dir, routine: routine, epoch: UUID()
        )

        let restore = try Fixtures.makeReadOnly(dir)
        store.quarantine(id: template.id, reason: "payloadTooLarge")
        restore()

        // The notice commits in the same write as the phase change: neither
        // survives, so the entry is still live and nothing was claimed.
        #expect(store.templateFailureNotices.isEmpty)
        #expect(store.entry(id: template.id)?.phase == .transportEligible)
    }

    @Test
    func aFailedRetirementWriteRecordsNoNotice() throws {
        let routine = Fixtures.makeWatchRoutine()
        let epoch = UUID()
        let dir = try Fixtures.makeTempDirectory()
        let (store, template, _) = try makeStoreWithPendingTemplateIntent(
            directory: dir, routine: routine, epoch: epoch
        )
        store.acknowledgeTemplateTransaction(
            ack(for: template, outcome: .rejected, routineEpoch: epoch, generation: 2)
        )

        let restore = try Fixtures.makeReadOnly(dir)
        store.applyRoutineContext([routine], header: RoutineSnapshotHeader(
            epoch: epoch, generation: 2, targetWatchInstanceID: nil, fromEpoch: nil, handoverNonce: nil
        ))
        restore()

        // Nothing became terminal, so nothing is claimed: the transaction is
        // still queued and its notice rolled back with it.
        #expect(store.templateFailureNotices.isEmpty)
        #expect(store.all.contains { $0.hasTemplateIntent })
    }

    // MARK: - Durability, dismissal, retention

    /// A terminal transfer failure can be reported again for bytes that are
    /// already quarantined. Re-recording would mint a new notice id and put a
    /// complaint the user dismissed back on their wrist.
    @Test
    func aRepeatedQuarantineOfTheSameEntryDoesNotResurrectADismissedNotice() throws {
        let routine = Fixtures.makeWatchRoutine()
        let dir = try Fixtures.makeTempDirectory()
        let (store, template, _) = try makeStoreWithPendingTemplateIntent(
            directory: dir, routine: routine, epoch: UUID()
        )
        store.quarantine(id: template.id, reason: "payloadTooLarge")
        let notice = try #require(store.templateFailureNotices.first)
        store.dismissTemplateFailureNotice(id: notice.id)

        store.quarantine(id: template.id, reason: "payloadTooLarge")

        #expect(store.templateFailureNotices.isEmpty)
    }

    @Test
    func aNoticeSurvivesRelaunchAndDismissalIsDurable() throws {
        let routine = Fixtures.makeWatchRoutine()
        let dir = try Fixtures.makeTempDirectory()
        let (store, template, _) = try makeStoreWithPendingTemplateIntent(
            directory: dir, routine: routine, epoch: UUID()
        )
        store.quarantine(id: template.id, reason: "payloadTooLarge")

        let relaunched = WatchSyncStateStore(directory: dir, legacyDefaults: nil)
        let notice = try #require(relaunched.templateFailureNotices.first)

        relaunched.dismissTemplateFailureNotice(id: notice.id)
        #expect(relaunched.templateFailureNotices.isEmpty)

        let afterDismissal = WatchSyncStateStore(directory: dir, legacyDefaults: nil)
        #expect(afterDismissal.templateFailureNotices.isEmpty)
    }

    @Test
    func aRepeatedFailureForTheSameRoutineSupersedesItsOlderNotice() throws {
        let routine = Fixtures.makeWatchRoutine()
        let dir = try Fixtures.makeTempDirectory()
        let (store, firstTemplate, _) = try makeStoreWithPendingTemplateIntent(
            directory: dir, routine: routine, epoch: UUID()
        )
        store.quarantine(id: firstTemplate.id, reason: "payloadTooLarge")

        let secondWorkout = Fixtures.makeWorkout(
            routineId: routine.id, routineName: routine.name, shouldUpdateTemplate: true
        )
        try store.enqueue(secondWorkout, phase: .transportEligible, routineAnchor: routine)
        let secondTemplate = try #require(
            Fixtures.templateEntry(in: store, forWorkout: secondWorkout.id)
        )
        store.quarantine(id: secondTemplate.id, reason: "payloadTooLarge")

        #expect(store.templateFailureNotices.count == 1)
        #expect(store.templateFailureNotices[0].reason == .couldNotSend)
    }

    @Test
    func noticesAreBoundedSoTheyStayANudgeAndNotALog() throws {
        let store = WatchSyncStateStore(
            directory: try Fixtures.makeTempDirectory(), legacyDefaults: nil
        )
        for index in 0..<(WatchTemplateFailureNotice.maxRetained + 3) {
            let routine = Fixtures.makeWatchRoutine(name: "Routine \(index)")
            let workout = Fixtures.makeWorkout(
                routineId: routine.id, routineName: routine.name, shouldUpdateTemplate: true
            )
            try store.enqueue(workout, phase: .transportEligible, routineAnchor: routine)
            let template = try #require(Fixtures.templateEntry(in: store, forWorkout: workout.id))
            store.quarantine(id: template.id, reason: "payloadTooLarge")
        }

        #expect(store.templateFailureNotices.count == WatchTemplateFailureNotice.maxRetained)
        // Newest first, and the oldest complaints were dropped.
        #expect(store.templateFailureNotices[0].routineName == "Routine 7")
    }
}
