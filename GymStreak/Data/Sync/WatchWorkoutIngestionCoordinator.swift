//
//  WatchWorkoutIngestionCoordinator.swift
//  GymStreak
//
//  Single serialized owner of the completed-watch-workout receive pipeline
//  (ticket 04, extended by ticket 05 of in-workout routine editing).
//  Constructed by the composition root (AppDependencies) — deliberately not a
//  ViewModel: payloads must be ingested even when no view exists, and
//  independent unstructured main-actor tasks must never determine mutation
//  order.
//
//  Drain triggers: launch (AppDependencies init), every persisted receipt of
//  a payload (WatchConnectivityManager.onWorkoutInboxUpdated), WCSession
//  activation, and the arrival of a watch routine challenge. Each drain
//  serially processes the durable inbox oldest-first:
//
//    receipt exists            → acknowledgment-only (no re-ingestion, even
//                                if the user has deleted the history entry)
//    no-template workout       → isolated single-save ingest, then durable
//                                receipt, then inbox removal + workoutAck
//    template intent           → delegated to WatchTemplateTransactionCoordinator
//                                (ordering, one-save commit, phased receipt,
//                                authoritative context, versioned ack)
//
//  Any failure keeps the inbox entry replayable and acknowledges nothing —
//  the watch's durable queue redelivers until convergence.
//

import Foundation

@MainActor
final class WatchWorkoutIngestionCoordinator {
    private let inbox: WatchWorkoutInboxStore
    private let receipts: WorkoutIngestReceiptStore
    private let historyTransactions: WorkoutHistoryTransacting
    private let watchSync: WatchSyncServicing
    private let templateTransactions: WatchTemplateTransactionCoordinator

    private var isDraining = false
    private var needsAnotherDrain = false

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
        self.watchSync = watchSync
        self.templateTransactions = WatchTemplateTransactionCoordinator(
            inbox: inbox,
            receipts: receipts,
            historyTransactions: historyTransactions,
            routineSnapshots: routineSnapshots,
            routineSnapshotTransport: routineSnapshotTransport,
            mainContextCache: mainContextCache,
            watchSync: watchSync
        )
    }

    /// Serially processes every inbox entry, oldest first. Reentrant calls
    /// coalesce into one follow-up pass, so mutation order is always the
    /// inbox's arrival order — never task-scheduling order.
    func drainInbox() {
        guard !isDraining else {
            needsAnotherDrain = true
            return
        }
        isDraining = true
        defer {
            isDraining = false
            if needsAnotherDrain {
                needsAnotherDrain = false
                drainInbox()
            }
        }

        for entry in inbox.entries() {
            process(entry)
        }
    }

    /// Called only when the watch's routine challenge changes. Ready receipts
    /// are otherwise intentionally quiet; ordinary inbox drains must not
    /// resend every historical terminal acknowledgment.
    func routineAuthorityDidChange() {
        templateTransactions.recoverReadyReceipts()
        drainInbox()
    }

    private func process(_ entry: WatchWorkoutInboxStore.Entry) {
        guard let workout = entry.completedWorkout else {
            _ = templateTransactions.process(entry)
            return
        }

        // A durable terminal receipt answers duplicates and lost-ack
        // redeliveries without re-ingestion — receipts survive history
        // deletion, so a deleted session is never resurrected.
        if let receipt = templateTransactions.receipt(for: entry) {
            if receipt.phase == .readyToAcknowledgeNotRequested {
                inbox.remove(entry)
                watchSync.acknowledgeWorkoutSaved(id: workout.id)
            } else {
                templateTransactions.resume(entry, receipt: receipt)
            }
            return
        }

        guard workout.shouldUpdateTemplate else {
            processNoTemplate(entry)
            return
        }

        if case .advancedSequence = templateTransactions.process(entry) {
            // The expected sequence moved on, so a successor buffered earlier
            // in this same pass (it was above the expected sequence then) is
            // now ingestible. Re-run once the current pass finishes rather
            // than recursing mid-iteration.
            needsAnotherDrain = true
        }
    }

    private func processNoTemplate(_ entry: WatchWorkoutInboxStore.Entry) {
        guard let workout = entry.completedWorkout else { return }

        // Isolated single-save context: unrelated dirty main-context work is
        // deferred — ingestion can neither save nor roll it back.
        let transaction = historyTransactions.makeIsolatedTransaction()
        let service = WatchWorkoutIngestionService(
            routineRepository: transaction.routineRepository,
            workoutSessionRepository: transaction.workoutSessionRepository
        )
        guard service.ingest(workout.toIncomingWatchWorkout()).shouldAcknowledge else {
            // Save failed: discard only this isolated context; the inbox entry
            // and the watch's durable queue stay intact, nothing is acked.
            transaction.rollback()
            return
        }

        // Terminal receipt BEFORE inbox removal and ack. If this write fails,
        // the entry stays replayable and nothing is acknowledged; the next
        // drain dedupes against the committed session and retries the receipt
        // (covers the migrated history-without-receipt case the same way).
        do {
            try receipts.record(WorkoutIngestReceipt(
                workoutId: workout.id,
                healthKitWorkoutId: workout.healthKitWorkoutId,
                phase: .readyToAcknowledgeNotRequested,
                recordedAt: Date()
            ))
        } catch {
            print("WatchWorkoutIngestionCoordinator: receipt write failed — keeping inbox entry for retry (\(error.localizedDescription))")
            return
        }

        inbox.remove(entry)
        watchSync.acknowledgeWorkoutSaved(id: workout.id)
    }
}
