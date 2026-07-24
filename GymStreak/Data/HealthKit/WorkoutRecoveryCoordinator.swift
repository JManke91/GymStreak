//
//  WorkoutRecoveryCoordinator.swift
//  GymStreak
//
//  App-lifetime engine for HealthKit-orphan recovery (ticket 09 of in-workout
//  routine editing). Wires the pieces together:
//
//    HKObserverQuery / foreground  →  anchored incremental drain  →  ledger
//    (apply deletions + discoveries idempotently)  →  persist anchor AFTER the
//    ledger commits  →  reconcile against live sync facts  →  publish the
//    candidates cleared for user-confirmed, history-only recovery.
//
//  Lives in the composition root (like WatchWorkoutIngestionCoordinator), not a
//  ViewModel, because discovery and reconciliation must run before any view
//  exists and must not depend on view lifecycles. The conservative policy lives
//  in the pure `WorkoutRecoveryReconciler`; this type only gathers facts and
//  applies the verdicts.
//

import Foundation

@MainActor
final class WorkoutRecoveryCoordinator: WorkoutRecoveryCoordinating {
    private let anchorStore: HealthKitWorkoutAnchorStore
    private let ledger: WorkoutRecoveryLedgerStore
    private let drain: HealthKitAnchoredWorkoutDrain
    private let observer: HealthKitWorkoutObserver
    private let historyCorrelation: WorkoutHistoryCorrelationProviding
    private let receipts: WorkoutIngestReceiptStore
    private let watchSync: WatchSyncServicing
    private let gracePeriod: TimeInterval
    private let now: () -> Date

    private(set) var recoverableWorkouts: [OrphanedWorkout] = []

    private var isDraining = false
    private var needsAnotherDrain = false

    init(
        anchorStore: HealthKitWorkoutAnchorStore,
        ledger: WorkoutRecoveryLedgerStore,
        drain: HealthKitAnchoredWorkoutDrain,
        observer: HealthKitWorkoutObserver,
        historyCorrelation: WorkoutHistoryCorrelationProviding,
        receipts: WorkoutIngestReceiptStore,
        watchSync: WatchSyncServicing,
        gracePeriod: TimeInterval = 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.anchorStore = anchorStore
        self.ledger = ledger
        self.drain = drain
        self.observer = observer
        self.historyCorrelation = historyCorrelation
        self.receipts = receipts
        self.watchSync = watchSync
        self.gracePeriod = gracePeriod
        self.now = now
    }

    /// Registers the long-lived observer (background wake signal) and runs the
    /// first drain. Call once at launch.
    func start() {
        observer.start { [weak self] in
            await self?.performDrainAndReconcile()
        }
        refresh()
    }

    // MARK: - WorkoutRecoveryCoordinating

    func refresh() {
        Task { await performDrainAndReconcile() }
    }

    func reconcile() {
        reconcileLedger()
    }

    func markPlaceholderSaved(externalUUID: UUID, sessionId: UUID) {
        guard var entry = ledger.entry(forExternalUUID: externalUUID) else { return }
        entry.state = .placeholderSaved
        entry.placeholderSessionId = sessionId
        try? ledger.upsert(entry)
        WorkoutRecoveryDiagnostics.logPlaceholderSaved(externalUUID: externalUUID)
        reconcileLedger()
    }

    func debugSummary() -> [String] {
        let facts = gatherFacts()
        let t = now()
        return ledger.entries()
            .sorted { $0.discoveredAt > $1.discoveredAt }
            .map { entry in
                let summary = WorkoutRecoveryReconciler.summaryState(
                    for: entry, context: facts.context(for: entry, gracePeriod: gracePeriod, now: t)
                )
                return WorkoutRecoveryDiagnostics.summaryLine(for: entry, summary: summary, now: t)
            }
    }

    // MARK: - Drain

    private func performDrainAndReconcile() async {
        guard !isDraining else { needsAnotherDrain = true; return }
        isDraining = true
        defer { isDraining = false }

        let anchor = anchorStore.loadAnchor()
        let bootstrap = anchor == nil
        let lowerBound = anchorStore.bootstrapLowerBound(now: now())

        let changes: HealthKitAnchoredWorkoutDrain.Changes
        do {
            changes = try await drain.drain(anchor: anchor, lowerBound: lowerBound)
        } catch {
            // Leave the anchor unchanged so the same changes replay; still
            // reconcile the existing ledger against current sync facts.
            WorkoutRecoveryDiagnostics.logDrainFailure(error)
            reconcileLedger()
            drainAgainIfNeeded()
            return
        }

        // Apply deletions then discoveries idempotently. If any ledger write
        // fails, do NOT advance the anchor — the drain replays next time.
        do {
            let t = now()
            for uuid in changes.deletedObjectUUIDs {
                ledger.applyDeleted(objectUUID: uuid, now: t)
            }
            for facts in changes.discovered {
                let entry = try ledger.applyDiscovered(facts, now: t)
                if entry.hasExternalUUIDConflict {
                    WorkoutRecoveryDiagnostics.logConflict(
                        externalUUID: entry.externalUUID, objectUUIDs: entry.healthKitObjectUUIDs
                    )
                }
            }
        } catch {
            WorkoutRecoveryDiagnostics.logDrainFailure(error)
            reconcileLedger()
            drainAgainIfNeeded()
            return
        }

        // Anchor committed only AFTER the ledger changes are durable.
        do {
            try anchorStore.save(anchor: changes.newAnchor)
        } catch {
            // Non-fatal: the next drain replays the same changes idempotently.
            WorkoutRecoveryDiagnostics.logAnchorReset(reason: "persist failed")
        }

        WorkoutRecoveryDiagnostics.logDrain(
            discovered: changes.discovered.count,
            deleted: changes.deletedObjectUUIDs.count,
            bootstrap: bootstrap
        )
        reconcileLedger()
        drainAgainIfNeeded()
    }

    private func drainAgainIfNeeded() {
        guard needsAnotherDrain else { return }
        needsAnotherDrain = false
        refresh()
    }

    // MARK: - Reconcile

    /// Live facts shared across all candidates in one reconcile pass.
    private struct Facts {
        let knownHistoryIDs: Set<UUID>
        let bufferedIDs: Set<UUID>
        let watchConnectivityMayDeliver: Bool

        func context(
            for entry: WorkoutRecoveryLedgerEntry,
            gracePeriod: TimeInterval,
            now: Date
        ) -> RecoveryReconciliationContext {
            RecoveryReconciliationContext(
                hasCommittedHistoryOrReceipt: knownHistoryIDs.contains(entry.externalUUID),
                isBufferedOrDraining: bufferedIDs.contains(entry.externalUUID),
                watchConnectivityMayDeliver: watchConnectivityMayDeliver,
                gracePeriod: gracePeriod,
                now: now
            )
        }
    }

    private func gatherFacts() -> Facts {
        let known = (try? historyCorrelation.healthKitWorkoutIDs()) ?? []
        let buffered = Set(watchSync.pendingWorkouts().compactMap(\.healthKitWorkoutId))
        return Facts(
            knownHistoryIDs: known,
            bufferedIDs: buffered,
            watchConnectivityMayDeliver: watchSync.mayHaveUndeliveredContent
        )
    }

    private func reconcileLedger() {
        guard let known = try? historyCorrelation.healthKitWorkoutIDs() else { return }
        let buffered = Set(watchSync.pendingWorkouts().compactMap(\.healthKitWorkoutId))
        let wcMayDeliver = watchSync.mayHaveUndeliveredContent
        let t = now()

        var offers: [OrphanedWorkout] = []
        for entry in ledger.entries() {
            var entry = entry
            // A receipt proves prior ingestion even if the user deleted history.
            let hasReceipt = receipts.receipt(forHealthKitWorkoutId: entry.externalUUID) != nil
            let hasCommitted = known.contains(entry.externalUUID) || hasReceipt

            let context = RecoveryReconciliationContext(
                hasCommittedHistoryOrReceipt: hasCommitted,
                isBufferedOrDraining: buffered.contains(entry.externalUUID),
                watchConnectivityMayDeliver: wcMayDeliver,
                gracePeriod: gracePeriod,
                now: t
            )

            if applyStateTransition(to: &entry, known: known, hasCommitted: hasCommitted) {
                try? ledger.upsert(entry)
            }

            switch WorkoutRecoveryReconciler.decide(for: entry, context: context) {
            case .offerRecovery:
                offers.append(OrphanedWorkout(ledgerEntry: entry))
            case .resolve, .postpone, .conflict:
                break
            }
        }

        offers.sort { $0.startDate > $1.startDate }
        publish(offers)
    }

    /// Advances terminal ledger state; returns whether the entry changed.
    private func applyStateTransition(
        to entry: inout WorkoutRecoveryLedgerEntry,
        known: Set<UUID>,
        hasCommitted: Bool
    ) -> Bool {
        // A rich payload replaced a saved placeholder: the committed session id
        // for this external UUID now differs from the placeholder's.
        if entry.state == .placeholderSaved,
           known.contains(entry.externalUUID),
           let placeholderId = entry.placeholderSessionId,
           let currentId = try? historyCorrelation.sessionID(forHealthKitWorkoutId: entry.externalUUID),
           currentId != placeholderId {
            entry.state = .placeholderReplaced
            return true
        }
        if entry.state == .provisional, hasCommitted {
            entry.state = .resolvedByHistory
            return true
        }
        return false
    }

    private func publish(_ offers: [OrphanedWorkout]) {
        guard offers != recoverableWorkouts else { return }
        recoverableWorkouts = offers
        NotificationCenter.default.post(name: .recoverableWorkoutsDidChange, object: nil)
    }
}
