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
    /// Taken around a **whole** drain pass, never inside it.
    ///
    /// The drain deletes rows the History model actor holds — `WatchWorkoutIngestionService`
    /// removes the HealthKit-recovered placeholder session it supersedes, and
    /// `WatchTemplateTransactionService.liveRoutine` removes a legacy placeholder `Routine`
    /// — so it is a writer like any other. See `HistoryStoreGate` and
    /// `docs/history-delete-race.md`.
    ///
    /// Gating the pass as a whole is deliberate, and is what makes this safe to do at all.
    /// Everything below stays **synchronous**: the reentrancy coalescing, the oldest-first
    /// ordering and the one-save-per-entry commits gain no suspension point, so none of
    /// their invariants change. Only the entry points are `async`. The internal follow-up
    /// pass therefore calls `drainInboxLocked()`, never `drainInbox()` — the gate is not
    /// reentrant, and re-entering it here would deadlock the pipeline.
    private let historyStoreGate: HistoryStoreGate

    private var isDraining = false
    private var needsAnotherDrain = false

    init(
        inbox: WatchWorkoutInboxStore,
        receipts: WorkoutIngestReceiptStore,
        historyTransactions: WorkoutHistoryTransacting,
        routineSnapshots: AuthoritativeRoutineSnapshotProviding,
        routineSnapshotTransport: WatchRoutineSnapshotTransporting,
        mainContextCache: MainContextRoutineCacheRefreshing,
        watchSync: WatchSyncServicing,
        historyStoreGate: HistoryStoreGate
    ) {
        self.inbox = inbox
        self.receipts = receipts
        self.historyTransactions = historyTransactions
        self.watchSync = watchSync
        self.historyStoreGate = historyStoreGate
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

    /// Serially processes every inbox entry, oldest first, holding the History gate for
    /// the whole pass — see `historyStoreGate` for why the gate is taken here rather than
    /// around the individual deletions inside.
    func drainInbox() async {
        await historyStoreGate.withAccess { drainInboxLocked() }
    }

    /// The pass itself. Reentrant calls coalesce into one follow-up pass, so mutation
    /// order is always the inbox's arrival order — never task-scheduling order.
    ///
    /// Synchronous on purpose, and the caller must already hold `historyStoreGate`.
    private func drainInboxLocked() {
        guard !isDraining else {
            needsAnotherDrain = true
            return
        }
        isDraining = true
        defer {
            isDraining = false
            if needsAnotherDrain {
                needsAnotherDrain = false
                // Not `drainInbox()`: the gate is already held and is not reentrant.
                drainInboxLocked()
            }
        }

        for entry in inbox.entries() {
            process(entry)
        }
    }

    /// Called only when the watch's routine challenge changes. Ready receipts
    /// are otherwise intentionally quiet; ordinary inbox drains must not
    /// resend every historical terminal acknowledgment.
    ///
    /// One gate acquisition covers the receipt recovery and the drain it triggers, so the
    /// two stay one atomic pass exactly as they were before.
    func routineAuthorityDidChange() async {
        await historyStoreGate.withAccess {
            templateTransactions.recoverReadyReceipts()
            drainInboxLocked()
        }
    }

    private func process(_ entry: WatchWorkoutInboxStore.Entry) {
        guard let workout = entry.completedWorkout else {
            // A template-only kind — progressive overload, or the split
            // template intent of a workout whose history travels as its own
            // entry — can advance the per-routine sequence too, which releases
            // a successor that was
            // visited earlier in this same pass and buffered because its
            // predecessor had not arrived yet. Same handling as the
            // completed-workout branch below — dropping the result here would
            // stall that successor until an unrelated external trigger.
            if case .advancedSequence = templateTransactions.process(entry) {
                needsAnotherDrain = true
            }
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
            WatchSyncDiagnostics.error("ingest: receipt write failed — keeping inbox entry for retry (\(error.localizedDescription))")
            return
        }

        inbox.remove(entry)
        watchSync.acknowledgeWorkoutSaved(id: workout.id)
    }
}
