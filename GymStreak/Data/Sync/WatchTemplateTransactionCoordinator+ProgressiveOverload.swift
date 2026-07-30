//
//  WatchTemplateTransactionCoordinator+ProgressiveOverload.swift
//  GymStreak
//
//  Receive-side handling for the template-only progressive-overload kind
//  (progressive-overload ticket 04). Split out of
//  `WatchTemplateTransactionCoordinator.swift` to keep both files within the
//  repository's file-length convention.
//
//  This adds NO protocol of its own. It reuses, unchanged:
//    • the serialized inbox and its arrival ordering;
//    • the per-(senderEpoch, routine) sequence ledger and FIFO head gate, which
//      is what orders an overload against a completed-workout template update;
//    • the fresh autosave-disabled isolated context and its single save;
//    • the `committedAwaitingContext` → `readyToAcknowledge` receipt phases and
//      the versioned terminal acknowledgment naming an exact routine
//      generation.
//
//  The only structural difference from the completed-workout kind is that the
//  receipt carries no workout correlation (`workoutId`/`healthKitWorkoutId` are
//  nil). The receipt store keys such a receipt by its transaction identity and
//  skips the correlation indexes, so nothing downstream needs a workout.
//

import Foundation

extension WatchTemplateTransactionCoordinator {
    /// Ingests one progressive-overload transaction. Mirrors the phase sequence
    /// of the completed-workout path exactly; only the executor differs, and it
    /// deliberately never fabricates history for a transaction that has no
    /// workout.
    func processProgressiveOverload(
        _ entry: WatchWorkoutInboxStore.Entry,
        intent: WatchProgressiveOverloadIntent
    ) -> Result {
        guard let transaction = entry.transaction, let key = entry.transactionKey else {
            // A progressive payload can only exist inside an envelope, so this
            // is unreachable in practice; retaining is the safe response.
            print("WatchTemplateTransaction: progressive overload without transaction identity — retained")
            return .unchanged
        }

        // A duplicate of an already-terminal transaction is answered from its
        // receipt without re-running the mutation.
        if let receipt = receipts.receipt(for: key) {
            guard receipt.transactionID == transaction.transactionID else {
                print("WatchTemplateTransaction: receipt key collision with mismatched transaction id — retained")
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
                print("WatchTemplateTransaction: overload sequence \(key.sequence) > expected \(expected) — buffered")
                return .unchanged
            }
            if key.sequence < expected {
                print("WatchTemplateTransaction: overload sequence \(key.sequence) < expected \(expected) with no receipt — inconsistent, retained")
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
        // Map the wire DTO into the Domain-owned input at this boundary, so the
        // Domain service never references a Codable sync type (same rule as
        // `CompletedWatchWorkout.toIncomingWatchWorkout()`).
        switch service.executeProgressiveOverload(
            intent.toIncomingProgressiveOverload(), routineID: key.routineID
        ) {
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
            // entry: the next drain re-applies the same absolute values
            // idempotently and retries the receipt.
            print("WatchTemplateTransaction: overload receipt write failed — \(error.localizedDescription)")
            return .unchanged
        }

        stageContextAndAcknowledge(entry, receipt: receipt)
        return .advancedSequence
    }
}
