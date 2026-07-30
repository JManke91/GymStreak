//
//  WatchTemplateTransactionCoordinator.swift
//  GymStreak
//
//  The template-transaction half of the watch receive pipeline (ticket 05,
//  in-workout routine editing). Split out of
//  `WatchWorkoutIngestionCoordinator`, which still owns the serialized inbox
//  drain and the no-template path and delegates here for anything carrying
//  template intent.
//
//  Phases for one transaction:
//
//    1. ordering — only the expected sequence for (senderEpoch, routine) may
//       ingest; a higher one stays durably inboxed, a lower one must resolve
//       from its receipt.
//    2. commit — history plus the complete set-only template update stage in
//       ONE isolated context and save exactly once, or the whole request is
//       terminally rejected with the routine left untouched.
//    3. committedAwaitingContext — the local outcome is final and durable.
//    4. readyToAcknowledge — the authoritative post-commit routine snapshot
//       has been staged, and only then is the versioned terminal
//       acknowledgment sent naming that exact routine generation.
//
//  Only a SwiftData save failure rolls back. Every failure after the commit
//  resumes from the persisted phase and never re-runs the mutation.
//

import Foundation

@MainActor
final class WatchTemplateTransactionCoordinator {
    private let inbox: WatchWorkoutInboxStore
    // Internal (not private) so the progressive-overload kind in
    // `+ProgressiveOverload.swift` uses the same ordering ledger and isolated
    // transaction factory rather than acquiring its own.
    let receipts: WorkoutIngestReceiptStore
    let historyTransactions: WorkoutHistoryTransacting
    private let routineSnapshots: AuthoritativeRoutineSnapshotProviding
    private let routineSnapshotTransport: WatchRoutineSnapshotTransporting
    private let mainContextCache: MainContextRoutineCacheRefreshing
    private let watchSync: WatchSyncServicing

    init(
        inbox: WatchWorkoutInboxStore,
        receipts: WorkoutIngestReceiptStore,
        historyTransactions: WorkoutHistoryTransacting,
        routineSnapshots: AuthoritativeRoutineSnapshotProviding,
        routineSnapshotTransport: WatchRoutineSnapshotTransporting,
        mainContextCache: MainContextRoutineCacheRefreshing,
        watchSync: WatchSyncServicing
    ) {
        self.inbox = inbox
        self.receipts = receipts
        self.historyTransactions = historyTransactions
        self.routineSnapshots = routineSnapshots
        self.routineSnapshotTransport = routineSnapshotTransport
        self.mainContextCache = mainContextCache
        self.watchSync = watchSync
    }

    /// Outcome of processing one entry, so the drain owner knows whether the
    /// expected sequence advanced (releasing a successor buffered earlier in
    /// the same pass).
    enum Result {
        case advancedSequence
        case unchanged
    }

    /// Resumes a transaction whose outcome is already durable. A
    /// `readyToAcknowledge` receipt is acknowledgment-only; a
    /// `committedAwaitingContext` one resumes ONLY authoritative context
    /// staging — never any SwiftData mutation.
    func resume(_ entry: WatchWorkoutInboxStore.Entry, receipt: WorkoutIngestReceipt) {
        guard repairDurableOrdering(for: receipt) else { return }
        switch receipt.phase {
        case .readyToAcknowledge:
            resumeReadyReceipt(receipt, entry: entry)
        case .committedAwaitingContext:
            stageContextAndAcknowledge(entry, receipt: receipt)
        case .readyToAcknowledgeNotRequested:
            // Not reachable in practice — the drain owner answers that phase
            // itself, and a transaction-keyed receipt never carries it — but a
            // plain acknowledgment is the safe response either way.
            inbox.remove(entry)
            if let workoutID = entry.completedWorkout?.id {
                watchSync.acknowledgeWorkoutSaved(id: workoutID)
            }
        }
    }

    /// Repairs/updates retained ready receipts when the watch publishes a new
    /// challenge after their inbox entries were removed. This is the crash- and
    /// rejected-proposal recovery path required by the authority protocol.
    func recoverReadyReceipts() {
        for receipt in receipts.readyTemplateReceipts() {
            guard repairDurableOrdering(for: receipt) else { continue }
            resumeReadyReceipt(receipt, entry: nil)
        }
    }

    func receipt(for entry: WatchWorkoutInboxStore.Entry) -> WorkoutIngestReceipt? {
        if let key = entry.transactionKey, let receipt = receipts.receipt(for: key) {
            return receiptMatchesEntry(receipt, entry: entry) ? receipt : nil
        }
        guard let workoutID = entry.completedWorkout?.id else { return nil }
        return receipts.receipt(for: workoutID)
    }

    func process(_ entry: WatchWorkoutInboxStore.Entry) -> Result {
        // Template-only kinds carry no workout. They share this coordinator's
        // ordering ledger, receipt phases, and acknowledgment protocol; only
        // the executor differs.
        if let intent = entry.transaction?.payload.progressiveOverload {
            return processProgressiveOverload(entry, intent: intent)
        }
        guard let workout = entry.completedWorkout else {
            print("WatchTemplateTransaction: unsupported payload retained for a newer executor")
            return .unchanged
        }

        // A payload without ordering identity comes from a pre-ticket-05 watch
        // build (or a legacy migrated entry): it cannot take part in sequenced
        // authority.
        guard let key = entry.transactionKey ?? transactionKey(for: workout) else {
            processUnsequencedLegacy(entry)
            return .unchanged
        }

        // A duplicate of an already-terminal transaction is answered from its
        // receipt even when the workout correlation differs.
        if let receipt = receipts.receipt(for: key) {
            guard receiptMatchesEntry(receipt, entry: entry) else {
                print("WatchTemplateTransaction: receipt key collision with mismatched semantic identity — retained")
                return .unchanged
            }
            resume(entry, receipt: receipt)
            return .unchanged
        }

        if let expected = receipts.nextExpectedSequence(for: key.senderEpoch, routineID: key.routineID) {
            if key.sequence > expected {
                // A later transaction overtook its predecessor (cross-channel
                // delivery is not causally ordered). Stay durably inboxed
                // without mutating anything; the head's arrival releases it.
                print("WatchTemplateTransaction: sequence \(key.sequence) > expected \(expected) — buffered")
                return .unchanged
            }
            if key.sequence < expected {
                // Below expected without a receipt is a consistency error we
                // must surface rather than guess at: acknowledging it would
                // claim an outcome that never happened.
                print("WatchTemplateTransaction: sequence \(key.sequence) < expected \(expected) with no receipt — inconsistent, retained")
                return .unchanged
            }
        }
        // No ledger yet: the first observed sequence establishes it. That is
        // what keeps an iOS reinstall (receipts gone) from deadlocking against
        // a watch that kept its epoch and per-routine counters.

        let transaction = historyTransactions.makeIsolatedTransaction()
        let service = WatchTemplateTransactionService(
            routineRepository: transaction.routineRepository,
            workoutSessionRepository: transaction.workoutSessionRepository,
            exerciseRepository: transaction.exerciseRepository
        )
        let outcome: TemplateTransactionOutcome
        switch service.execute(workout.toIncomingWatchWorkout()) {
        case .applied:
            outcome = .applied
        case .rejected:
            outcome = .rejected
        case .saveFailed:
            // Only a save failure rolls back. Both queues stay; nothing acked.
            transaction.rollback()
            return .unchanged
        }

        // The local commit is final from here on. A failure below never
        // re-runs the mutation — it resumes from the persisted phase.
        let receipt = WorkoutIngestReceipt(
            workoutId: workout.id,
            healthKitWorkoutId: workout.healthKitWorkoutId,
            phase: .committedAwaitingContext,
            recordedAt: Date(),
            transactionID: entry.transaction?.transactionID ?? workout.templateTransactionID,
            senderEpoch: key.senderEpoch,
            routineID: key.routineID,
            sequence: key.sequence,
            outcomeRaw: outcome.rawValue,
            protocolVersion: WatchRoutineSync.templateUpdateVersion
        )
        do {
            try receipts.record(receipt)
            try receipts.advanceExpectedSequence(for: key)
        } catch {
            // The mutation committed but the receipt did not. Keep the inbox
            // entry: the next drain discovers the committed result
            // idempotently (the executor re-applies identical values and
            // dedupes history) and retries the receipt.
            print("WatchTemplateTransaction: receipt write failed — \(error.localizedDescription)")
            return .unchanged
        }

        stageContextAndAcknowledge(entry, receipt: receipt)
        return .advancedSequence
    }

    // MARK: - Authoritative context + acknowledgment

    /// Stages the authoritative post-commit routine snapshot and, once a
    /// routine authority has accepted a version for it, persists
    /// `readyToAcknowledge` and sends the terminal acknowledgment. Until then
    /// (no watch challenge yet) the receipt stays `committedAwaitingContext`
    /// and the inbox entry is retained so a later drain completes it.
    /// Internal (not private) so every transaction kind — including the
    /// progressive-overload kind in `+ProgressiveOverload.swift` — reaches its
    /// terminal receipt/acknowledgment through this one phase sequence.
    func stageContextAndAcknowledge(_ entry: WatchWorkoutInboxStore.Entry?, receipt: WorkoutIngestReceipt) {
        let snapshot: [WatchRoutine]
        do {
            snapshot = try routineSnapshots.fetchSnapshot()
        } catch {
            print("WatchTemplateTransaction: authoritative snapshot read failed — \(error.localizedDescription)")
            return
        }

        // Refreshing Presentation state is independent of the authoritative
        // wire snapshot. The cache refresher refuses to save/rollback unrelated
        // dirty main-context work.
        mainContextCache.refreshCache(from: snapshot)
        refreshMainContextCaches()

        guard let version = routineSnapshotTransport.stageAuthoritativeRoutineSnapshot(snapshot) else {
            print("WatchTemplateTransaction: no routine authority yet — transaction stays awaiting context")
            return
        }

        let staged = WorkoutIngestReceipt(
            workoutId: receipt.workoutId,
            healthKitWorkoutId: receipt.healthKitWorkoutId,
            phase: .readyToAcknowledge,
            recordedAt: receipt.recordedAt,
            transactionID: receipt.transactionID,
            senderEpoch: receipt.senderEpoch,
            routineID: receipt.routineID,
            sequence: receipt.sequence,
            outcomeRaw: receipt.outcomeRaw,
            protocolVersion: receipt.protocolVersion,
            routineEpoch: version.epoch,
            routineGeneration: version.generation
        )
        do {
            try receipts.record(staged)
        } catch {
            print("WatchTemplateTransaction: readyToAcknowledge write failed — \(error.localizedDescription)")
            return
        }
        if let entry { inbox.remove(entry) }
        sendTerminalAck(for: staged)
    }

    private func resumeReadyReceipt(
        _ receipt: WorkoutIngestReceipt,
        entry: WatchWorkoutInboxStore.Entry?
    ) {
        guard let routineEpoch = receipt.routineEpoch,
              let routineGeneration = receipt.routineGeneration else {
            return
        }
        guard let challenge = watchSync.watchRoutineChallenge else {
            if let entry { inbox.remove(entry) }
            sendTerminalAck(for: receipt)
            return
        }
        if challenge.epoch == routineEpoch, challenge.generation >= routineGeneration {
            if let entry { inbox.remove(entry) }
            receipts.markReadyRecoverySatisfied(receipt)
            sendTerminalAck(for: receipt)
        } else {
            // The watch did not accept (or has since retired) the staged
            // authority. Restage current authoritative routines and replace
            // the receipt's correlated version without re-running mutation.
            stageContextAndAcknowledge(entry, receipt: receipt)
        }
    }

    private func repairDurableOrdering(for receipt: WorkoutIngestReceipt) -> Bool {
        guard let key = receipt.transactionKey else { return true }
        do {
            // Re-recording repairs a correlation-index write that may have
            // failed after the primary receipt file committed.
            try receipts.record(receipt)
            try receipts.advanceExpectedSequence(for: key)
            return true
        } catch {
            print("WatchTemplateTransaction: ordering repair failed — \(error.localizedDescription)")
            return false
        }
    }

    private func sendTerminalAck(for receipt: WorkoutIngestReceipt) {
        guard let transactionID = receipt.transactionID,
              let key = receipt.transactionKey,
              let outcome = receipt.outcome,
              let routineEpoch = receipt.routineEpoch,
              let routineGeneration = receipt.routineGeneration else {
            // Never downgrade a template outcome to a plain acknowledgment:
            // a plain ack cannot prove template intent was processed.
            print("WatchTemplateTransaction: malformed terminal receipt retained")
            return
        }
        watchSync.acknowledgeTemplateTransaction(WatchTemplateTransactionAck(
            workoutId: receipt.workoutId,
            transactionID: transactionID,
            outcome: outcome,
            senderEpoch: key.senderEpoch,
            sequence: key.sequence,
            routineEpoch: routineEpoch,
            routineGeneration: routineGeneration
        ))
    }

    // MARK: - Mixed-version payloads

    /// A requested-template payload from a build that predates transaction
    /// identities. It may run the idempotent set-only reconciliation only
    /// while no sequenced authority exists for its routine; once any sequenced
    /// outcome is terminal for that routine, an unsequenced payload can never
    /// overwrite known newer state, so its template intent is terminally
    /// rejected while history is still preserved.
    private func processUnsequencedLegacy(_ entry: WatchWorkoutInboxStore.Entry) {
        guard let workout = entry.completedWorkout else { return }
        let transaction = historyTransactions.makeIsolatedTransaction()

        if receipts.hasSequencedOutcome(forRoutine: workout.routineId) {
            let service = WatchTemplateTransactionService(
                routineRepository: transaction.routineRepository,
                workoutSessionRepository: transaction.workoutSessionRepository,
                exerciseRepository: transaction.exerciseRepository
            )
            guard case .rejected = service.executeHistoryOnlyRejection(
                workout.toIncomingWatchWorkout()
            ) else {
                transaction.rollback()
                return
            }
            print("WatchTemplateTransaction: unsequenced legacy template intent rejected — newer sequenced state exists")
        } else {
            let service = WatchTemplateTransactionService(
                routineRepository: transaction.routineRepository,
                workoutSessionRepository: transaction.workoutSessionRepository,
                exerciseRepository: transaction.exerciseRepository
            )
            switch service.execute(workout.toIncomingWatchWorkout()) {
            case .saveFailed:
                transaction.rollback()
                return
            case .applied, .rejected:
                break
            }
        }

        do {
            try receipts.record(WorkoutIngestReceipt(
                workoutId: workout.id,
                healthKitWorkoutId: workout.healthKitWorkoutId,
                phase: .readyToAcknowledgeNotRequested,
                recordedAt: Date()
            ))
        } catch {
            print("WatchTemplateTransaction: legacy receipt write failed — \(error.localizedDescription)")
            return
        }
        // Old-watch payloads have no transaction generation to correlate, but
        // they still receive fresh committed state before the plain ack.
        guard let snapshot = try? routineSnapshots.fetchSnapshot() else {
            print("WatchTemplateTransaction: legacy authoritative snapshot read failed — retained")
            return
        }
        mainContextCache.refreshCache(from: snapshot)
        refreshMainContextCaches()
        routineSnapshotTransport.syncRoutineSnapshot(snapshot)
        inbox.remove(entry)
        // An old watch build only understands the plain acknowledgment.
        watchSync.acknowledgeWorkoutSaved(id: workout.id)
    }

    // MARK: - Helpers

    /// The ordering identity of a template transaction, or nil for a payload
    /// from a build that predates them.
    private func transactionKey(for workout: CompletedWatchWorkout) -> TemplateTransactionKey? {
        guard let senderEpoch = workout.templateSenderEpoch,
              let sequence = workout.templateSequence,
              workout.templateTransactionID != nil else { return nil }
        return TemplateTransactionKey(
            senderEpoch: senderEpoch, routineID: workout.routineId, sequence: sequence
        )
    }

    private func receiptMatchesEntry(
        _ receipt: WorkoutIngestReceipt,
        entry: WatchWorkoutInboxStore.Entry
    ) -> Bool {
        let transactionID = entry.transaction?.transactionID
            ?? entry.completedWorkout?.templateTransactionID
        guard transactionID != nil, receipt.transactionID == transactionID else { return false }
        if let receiptWorkoutID = receipt.workoutId,
           let entryWorkoutID = entry.completedWorkout?.id,
           receiptWorkoutID != entryWorkoutID {
            return false
        }
        return true
    }

    /// Refreshes routine/history UI caches through the main context after a
    /// committed transaction, WITHOUT invoking the ordinary routine-sync side
    /// effect: the watch's authoritative snapshot must come only from the
    /// post-save state staged above, so a stale retained main-context model
    /// can never emit a competing higher generation.
    private func refreshMainContextCaches() {
        NotificationCenter.default.post(name: .routineTemplateDidChangeLocally, object: nil)
    }
}
