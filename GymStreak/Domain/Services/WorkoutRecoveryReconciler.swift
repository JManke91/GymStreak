//
//  WorkoutRecoveryReconciler.swift
//  GymStreak
//
//  The conservative recovery policy (ticket 09 of in-workout routine editing).
//  Pure, deterministic logic: given one recovery-ledger candidate and the
//  current sync facts, it decides whether the candidate is resolved, must stay
//  provisional, may be offered for user-confirmed recovery, or is a diagnosed
//  conflict. It NEVER reconstructs anything itself — it only classifies.
//
//  The central correctness rule (see docs/watch-sync.md): no timeout and no
//  `WCSession.hasContentPending == false` is ever treated as proof that watch
//  payload delivery has finished. `hasContentPending == true` is positive-only
//  evidence to postpone; `false` says nothing (it only reports this device's
//  local receive queue, never the watch's send queue or HealthKit sync). The
//  grace period is UX policy, not a correctness boundary — after it elapses the
//  UI may *offer* recovery, but the user must confirm and a later rich payload
//  can still replace the result.
//

import Foundation

/// Why a candidate is being held back instead of offered. Surfaced in
/// diagnostics only.
enum RecoveryPostponeReason: String, Equatable, Sendable {
    /// The exact rich payload is buffered in the app-owned inbox / being
    /// ingested. Wait for that durable work to reach a terminal result.
    case inboxInFlight
    /// `WCSession.hasContentPending == true` (or the session hasn't activated)
    /// — WatchConnectivity may still deliver locally. Positive-only signal.
    case watchConnectivityPending
    /// Still inside the product grace period since first discovery.
    case withinGracePeriod
}

/// The reconciler's verdict for one candidate.
enum RecoveryDecision: Equatable, Sendable {
    /// Rich history or a terminal receipt exists — resolve without
    /// reconstruction.
    case resolve
    /// Keep the candidate provisional and re-check on the next trigger.
    case postpone(RecoveryPostponeReason)
    /// The grace period has elapsed with no proof of pending delivery. The UI
    /// may offer explicit, user-confirmed, history-only recovery.
    case offerRecovery
    /// More than one HealthKit object shares this external UUID. Diagnose;
    /// never reconstruct (would risk duplicate history).
    case conflict
}

/// The observable sync facts for a single candidate at reconciliation time.
struct RecoveryReconciliationContext: Sendable {
    /// Rich history OR a durable terminal ingest receipt exists for this
    /// workout / external UUID.
    let hasCommittedHistoryOrReceipt: Bool
    /// The exact rich payload is present in the app-owned inbox or actively
    /// being ingested.
    let isBufferedOrDraining: Bool
    /// WatchConnectivity may still be holding undelivered local content
    /// (`hasContentPending == true`, or the session hasn't activated). This is
    /// the ONLY WatchConnectivity fact allowed to postpone.
    let watchConnectivityMayDeliver: Bool
    let gracePeriod: TimeInterval
    let now: Date
}

enum WorkoutRecoveryReconciler {
    /// Classifies one candidate. Order matters: terminal proof first, conflict
    /// before any offer, then the layered postpone gates, then — and only then
    /// — an offer.
    static func decide(
        for entry: WorkoutRecoveryLedgerEntry,
        context: RecoveryReconciliationContext
    ) -> RecoveryDecision {
        // Already-terminal ledger states need no further action.
        switch entry.state {
        case .resolvedByHistory, .placeholderReplaced, .tombstoned:
            return .resolve
        case .provisional, .placeholderSaved:
            break
        }

        // 1. Rich history / terminal receipt is definitive.
        if context.hasCommittedHistoryOrReceipt {
            return .resolve
        }

        // A placeholder already exists: it stays until a rich payload replaces
        // it (handled by the ingestion path). Never offer it again.
        if entry.state == .placeholderSaved {
            return .resolve
        }

        // 2. A duplicate external UUID must be diagnosed, never reconstructed.
        if entry.hasExternalUUIDConflict {
            return .conflict
        }

        // 3. The exact payload is already durable work in flight.
        if context.isBufferedOrDraining {
            return .postpone(.inboxInFlight)
        }

        // 4. Positive-only WatchConnectivity evidence.
        if context.watchConnectivityMayDeliver {
            return .postpone(.watchConnectivityPending)
        }

        // 5. Grace period — UX policy, not a correctness boundary.
        if context.now.timeIntervalSince(entry.discoveredAt) < context.gracePeriod {
            return .postpone(.withinGracePeriod)
        }

        // 6. No proof of pending delivery remains. Offer user-confirmed,
        //    history-only recovery (which stays replaceable).
        return .offerRecovery
    }
}

/// A candidate's best-known position in the payload → inbox → history/receipt →
/// placeholder/replacement pipeline, for the bounded support/debug summary.
/// Deliberately distinguishes genuinely-unknown remote progress from any local
/// fact: an unknown position stays `.unknown` and is NEVER inferred from
/// `hasContentPending == false`.
enum WorkoutRecoverySummaryState: String, Equatable, Sendable {
    /// Rich history / terminal receipt committed. Terminal.
    case historyCommitted
    /// A later rich payload has replaced the placeholder. Terminal.
    case placeholderReplaced
    /// A user-confirmed history-only placeholder exists, awaiting possible
    /// replacement.
    case placeholder
    /// More than one HealthKit object shares this external UUID.
    case conflict
    /// The exact rich payload is buffered/inboxed locally, ingestion pending.
    case receivedInboxed
    /// Inboxed but its last ingest attempt recorded an error (deferred/retry).
    case ingestDeferred
    /// WatchConnectivity reports undelivered local content (`hasContentPending
    /// == true`). Transport is outstanding on THIS device.
    case outstandingTransport
    /// Past the grace period, nothing pending locally: a HealthKit-only
    /// candidate the UI may offer for recovery.
    case healthKitOnlyCandidate
    /// Provisional, within grace, nothing locally pending — we simply do not
    /// know whether the watch still holds a payload. Never claimed as settled.
    case unknown
}

extension WorkoutRecoveryReconciler {
    /// Pure projection of a candidate onto the diagnostic summary. `now` and
    /// `gracePeriod` come from `context`; `hasIngestError` distinguishes an
    /// inboxed-but-deferred entry from a fresh one.
    static func summaryState(
        for entry: WorkoutRecoveryLedgerEntry,
        context: RecoveryReconciliationContext
    ) -> WorkoutRecoverySummaryState {
        switch entry.state {
        case .resolvedByHistory:
            return .historyCommitted
        case .placeholderReplaced:
            return .placeholderReplaced
        case .placeholderSaved:
            return .placeholder
        case .tombstoned:
            return .historyCommitted
        case .provisional:
            break
        }

        if context.hasCommittedHistoryOrReceipt { return .historyCommitted }
        if entry.hasExternalUUIDConflict { return .conflict }
        if context.isBufferedOrDraining {
            return entry.lastError == nil ? .receivedInboxed : .ingestDeferred
        }
        if context.watchConnectivityMayDeliver { return .outstandingTransport }
        if context.now.timeIntervalSince(entry.discoveredAt) >= context.gracePeriod {
            return .healthKitOnlyCandidate
        }
        return .unknown
    }
}
