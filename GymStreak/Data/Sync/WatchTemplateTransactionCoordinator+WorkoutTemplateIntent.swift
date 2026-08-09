//
//  WatchTemplateTransactionCoordinator+WorkoutTemplateIntent.swift
//  GymStreak
//
//  Receive-side handling for split template intent — the template half of a
//  workout whose history travels as its own ungated sync entry
//  (`docs/adr/0001-split-workout-history-from-template-intent.md`). Split out
//  of `WatchTemplateTransactionCoordinator.swift` to keep both files within the
//  repository's file-length convention.
//
//  This adds NO protocol of its own. It reuses, unchanged: the serialized
//  inbox and its arrival ordering, the per-(senderEpoch, routine) sequence
//  ledger and FIFO head gate, the isolated single-save transaction, the
//  `committedAwaitingContext` → `readyToAcknowledge` receipt phases, and the
//  versioned terminal acknowledgment. It also reuses the completed-workout
//  EXECUTOR unchanged, which is what makes the two payloads converge in either
//  arrival order: `execute` stages history idempotently, so it commits the
//  wrapped copy when the history entry has not arrived yet and dedupes against
//  the committed session when it already has.
//
//  Two identity rules make the split safe, and both are load-bearing:
//    • the ENVELOPE's `workoutID` is nil, so the watch's `entry(id:)` cannot
//      collapse the workout's two sync entries into one;
//    • the RECEIPT's `workoutId`/`healthKitWorkoutId` are nil, so this receipt
//      is keyed by transaction identity only. A workout-correlated template
//      receipt would answer the separate history entry from the wrong receipt
//      and send a template acknowledgment instead of the plain one the history
//      entry needs to retire.
//

import Foundation

extension WatchTemplateTransactionCoordinator {
    /// Ingests one split template transaction: the routine update, plus the
    /// wrapped workout's history if its own entry has not been committed yet.
    func processWorkoutTemplateIntent(
        _ entry: WatchWorkoutInboxStore.Entry,
        workout: CompletedWatchWorkout
    ) -> Result {
        guard let transaction = entry.transaction, let key = entry.transactionKey else {
            // Split template intent can only exist inside an envelope, so this
            // is unreachable in practice; retaining is the safe response.
            WatchSyncDiagnostics.error("ingest: split template intent without transaction identity — retained")
            return .unchanged
        }

        // A duplicate of an already-terminal transaction is answered from its
        // receipt without re-running the mutation.
        if let receipt = receipts.receipt(for: key) {
            guard receipt.transactionID == transaction.transactionID else {
                WatchSyncDiagnostics.error("ingest: split template receipt key collision with mismatched transaction id — retained")
                return .unchanged
            }
            resume(entry, receipt: receipt)
            return .unchanged
        }

        if let expected = receipts.nextExpectedSequence(for: key.senderEpoch, routineID: key.routineID) {
            if key.sequence > expected {
                // Its predecessor has not been ingested yet (cross-channel
                // delivery is not causally ordered). Stay durably inboxed
                // without mutating anything.
                WatchSyncDiagnostics.notice("ingest: split template sequence \(key.sequence) > expected \(expected) — buffered awaiting predecessor")
                return .unchanged
            }
            if key.sequence < expected {
                WatchSyncDiagnostics.fault("ingest: split template sequence \(key.sequence) < expected \(expected) with no receipt — inconsistent, retained")
                return .unchanged
            }
        }

        let isolated = historyTransactions.makeIsolatedTransaction()
        let service = WatchTemplateTransactionService(
            routineRepository: isolated.routineRepository,
            workoutSessionRepository: isolated.workoutSessionRepository,
            exerciseRepository: isolated.exerciseRepository
        )
        let outcome: TemplateTransactionOutcome
        switch service.execute(workout.toIncomingWatchWorkout()) {
        case .applied:
            outcome = .applied
        case .rejected:
            outcome = .rejected
        case .saveFailed:
            // Only a save failure rolls back. Nothing is acknowledged, so the
            // watch's durable FIFO redelivers.
            isolated.rollback()
            return .unchanged
        }

        // The local commit is final from here on; failures below resume from
        // the persisted phase and never re-run the mutation.
        let receipt = WorkoutIngestReceipt(
            workoutId: nil,
            healthKitWorkoutId: nil,
            phase: .committedAwaitingContext,
            recordedAt: Date(),
            transactionID: transaction.transactionID,
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
            // entry: the next drain short-circuits on the atomic transaction
            // witness written into the session and retries the receipt.
            WatchSyncDiagnostics.error("ingest: split template receipt write failed — \(error.localizedDescription)")
            return .unchanged
        }

        stageContextAndAcknowledge(entry, receipt: receipt)
        return .advancedSequence
    }
}
