//
//  WatchWorkoutFinalizer.swift
//  GymStreakWatch Watch App
//
//  Terminal finalization state machine for ending a watch workout
//  (ticket 04, in-workout routine editing). One sequence shared by manual
//  End, auto-finish, and future structural-editing UI:
//
//    1. Freeze exactly one payload per workout id in the durable queue
//       (phase `awaitingHealthKitMetadata`) BEFORE any irreversible
//       HealthKit transition. A failed queue write aborts with no external
//       side effect, so the caller may return to editing.
//    2. Stamp the REQUIRED HKMetadataKeyExternalUUID (+ routine metadata)
//       on the live builder. Failure keeps the frozen payload for retry.
//    3. Finish the same HealthKit workout/builder. Failure is recovery-only:
//       a retry re-enters with the same bytes and identifiers.
//    4. Atomically advance to `transportEligible`, then hand off to the
//       transport owner. Transport never re-invokes payload construction
//       or HealthKit finalization.
//
//  Retries re-enter `finalize` with the same workout id: the frozen queue
//  entry (bytes + phase) decides which steps still run — payloads are never
//  reconstructed and completed HealthKit steps are never repeated.
//
//  IDENTICAL COPY in both targets — `GymStreak/Data/Sync/` and
//  `GymStreakWatch Watch App/Managers/` — keep them in sync. There is no
//  watch unit-test target, so the iOS test target covers this logic.
//

import Foundation

/// The HealthKit steps the finalizer sequences. Implemented by
/// `WatchHealthKitManager` on the watch; by fakes in the iOS test target.
@MainActor
protocol WorkoutFinalizationHealthKit: AnyObject {
    /// Ends live collection and stamps the required external-UUID metadata
    /// (GymStreak's cross-device correlation key — HealthKit itself neither
    /// requires nor dedupes it). Must throw on failure; the error is never
    /// swallowed into a transportable state. Idempotent across retries.
    func endCollectionAndAddMetadata(externalId: UUID) async throws
    /// Finishes the same workout/builder. Must throw on failure.
    func finishWorkout() async throws
}

@MainActor
final class WatchWorkoutFinalizer {
    enum Outcome {
        /// The durable queue write failed — no external side effect occurred;
        /// the caller may return to editing.
        case notEnqueued(Error)
        /// The payload is frozen and durable, but HealthKit finalization (or
        /// the phase-advance write) failed. Retry-only: re-enter with the
        /// same workout id.
        case healthKitFailed(Error)
        /// A finalization for another End action is already in flight —
        /// duplicate/reentrant End actions are rejected.
        case rejectedReentrant
        /// Finalized; the payload is transport-eligible and the transport
        /// owner has been triggered.
        case completed
    }

    private let syncState: WatchSyncStateStore
    private(set) var isFinalizing = false

    init(syncState: WatchSyncStateStore) {
        self.syncState = syncState
    }

    /// Runs the terminal finalization sequence. `payload` is only consulted
    /// on the first attempt for a workout id; retries reuse the frozen queue
    /// entry. `healthKit` is nil when there is no live HealthKit workout to
    /// finalize (UI testing, or the session never started).
    ///
    /// `onFrozen` fires exactly once, immediately after the durable enqueue
    /// succeeds and BEFORE any HealthKit work — at that point the workout is
    /// guaranteed to reach iOS regardless of the HealthKit outcome, so the UI
    /// can show its completion/summary without waiting on (or being blocked
    /// by) HealthKit finalization. It is NOT called when the enqueue fails
    /// (`.notEnqueued`) or on a reentrant rejection. On a retry of an
    /// already-frozen workout it fires again (idempotent for callers).
    func finalize(
        _ payload: CompletedWatchWorkout,
        healthKit: WorkoutFinalizationHealthKit?,
        routineAnchor: WatchRoutine? = nil,
        onFrozen: () -> Void = {},
        onTransportEligible: () -> Void
    ) async -> Outcome {
        guard !isFinalizing else { return .rejectedReentrant }
        isFinalizing = true
        defer { isFinalizing = false }

        // Step 1 — durable freeze before any irreversible end transition. For
        // a template transaction this same commit allocates the transaction
        // identity (id, sender epoch, per-routine sequence) and retains the
        // routine anchor, so nothing is sent or optimistically applied before
        // its ordering identity is durable.
        let entry: OutgoingSyncEntry
        do {
            entry = try syncState.enqueue(
                payload, phase: .awaitingHealthKitMetadata, routineAnchor: routineAnchor
            )
        } catch {
            return .notEnqueued(error)
        }

        // The workout is now durable and will reach iOS no matter how the
        // HealthKit steps below turn out. Let the UI proceed before HealthKit.
        onFrozen()

        guard let workout = entry.completedWorkout else {
            return .healthKitFailed(CocoaError(.coderInvalidValue))
        }
        let workoutId = workout.id
        var phase = entry.phase

        // Steps 2+3 — phased HealthKit finalization on the frozen identity.
        if phase == .awaitingHealthKitMetadata {
            if let healthKit {
                guard let externalId = workout.healthKitWorkoutId else {
                    return .healthKitFailed(CocoaError(.coderInvalidValue))
                }
                do {
                    try await healthKit.endCollectionAndAddMetadata(externalId: externalId)
                } catch {
                    return .healthKitFailed(error)
                }
            }
            do {
                try syncState.advance(id: workoutId, to: .awaitingHealthKitFinish)
                phase = .awaitingHealthKitFinish
            } catch {
                return .healthKitFailed(error)
            }
        }

        if phase == .awaitingHealthKitFinish {
            if let healthKit {
                do {
                    try await healthKit.finishWorkout()
                } catch {
                    return .healthKitFailed(error)
                }
            }
            do {
                try syncState.advance(id: workoutId, to: .transportEligible)
                phase = .transportEligible
            } catch {
                return .healthKitFailed(error)
            }
        }

        guard phase == .transportEligible else {
            // Quarantined (or unexpected) — never transport these bytes.
            return .healthKitFailed(CocoaError(.coderInvalidValue))
        }

        // Step 4 — transport is a separate concern operating on the durable
        // queue; triggering it again for an already-eligible entry is safe
        // (iOS dedupes on the workout id).
        onTransportEligible()
        return .completed
    }
}
