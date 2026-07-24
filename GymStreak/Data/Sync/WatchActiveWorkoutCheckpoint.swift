//
//  WatchActiveWorkoutCheckpoint.swift
//  GymStreakWatch Watch App
//
//  Ticket 08 (in-workout routine editing): the minimum app-owned snapshot of a
//  live watch workout, persisted so the workout survives watchOS terminating
//  and relaunching GymStreak mid-session.
//
//  Apple's `HKHealthStore.recoverActiveWorkoutSession` restores ONLY the still
//  -active `HKWorkoutSession` — never GymStreak's exercises, navigation, stable
//  identifiers, structural provenance, or template intent. This checkpoint
//  carries everything needed to rebuild `WatchWorkoutViewModel` around a
//  recovered (or lost) HealthKit session, keyed by identifiers preallocated at
//  workout start so recovery never mints a second workout/HealthKit record.
//
//  Persisted by `WatchActiveWorkoutCheckpointStore` as a throwing, atomically
//  replaced App Group file (NOT `UserDefaults` — the crash boundary must be a
//  single atomic replace, mirroring `WatchSyncStateStore`). Written at bounded
//  meaningful mutations (set completion, value/rest edits, swaps, add/remove,
//  navigation) — never on sensor samples or high-frequency statistics.
//
//  IDENTICAL COPY in both targets — `GymStreak/Data/Sync/` and
//  `GymStreakWatch Watch App/Models/` — keep them in sync. There is no watch
//  unit-test target, so the iOS test target covers this logic.
//

import Foundation

/// The durable app-owned snapshot of an in-progress watch workout.
struct WatchActiveWorkoutCheckpoint: Codable, Equatable {
    /// Schema version so a future field addition stays backward-decodable.
    var version: Int
    /// Stable GymStreak workout UUID — `CompletedWatchWorkout.id` and the
    /// correlation key for the durable outgoing entry. Preallocated at workout
    /// start so a crash mid-workout never mints a new one on resume.
    var workoutID: UUID
    /// Preallocated HealthKit external UUID (`HKMetadataKeyExternalUUID`). Stable
    /// across relaunch so recovery reconciles the exact saved `HKWorkout` and
    /// never records a second one.
    var healthKitWorkoutID: UUID
    /// The routine as resolved at workout start (identity + name + planned
    /// structure). Restored verbatim on resume — never re-resolved from the
    /// store, which may have changed since.
    var routine: WatchRoutine
    /// Live exercise/set state with stable slot/set IDs, completion values,
    /// swap metadata, and pending-Watch-addition provenance.
    var exercises: [ActiveWorkoutExercise]
    var currentExerciseIndex: Int
    var currentSetIndex: Int
    var startTime: Date
    /// Ticket 06 structural baseline, so add/remove membership intent survives
    /// relaunch and a later removal can still cancel a pending addition.
    var structuralBaseline: WatchWorkoutStructuralBaseline

    static let currentVersion = 1

    init(
        workoutID: UUID,
        healthKitWorkoutID: UUID,
        routine: WatchRoutine,
        exercises: [ActiveWorkoutExercise],
        currentExerciseIndex: Int,
        currentSetIndex: Int,
        startTime: Date,
        structuralBaseline: WatchWorkoutStructuralBaseline,
        version: Int = WatchActiveWorkoutCheckpoint.currentVersion
    ) {
        self.version = version
        self.workoutID = workoutID
        self.healthKitWorkoutID = healthKitWorkoutID
        self.routine = routine
        self.exercises = exercises
        self.currentExerciseIndex = currentExerciseIndex
        self.currentSetIndex = currentSetIndex
        self.startTime = startTime
        self.structuralBaseline = structuralBaseline
    }
}

/// The recovery action for a relaunched workout, derived purely from durable
/// facts (see `WatchWorkoutRecoveryPlanner`). Kept HealthKit-free so the
/// crash-point classification is exhaustively unit-testable.
enum WatchWorkoutRecoveryDecision: Equatable {
    /// Nothing to recover.
    case none
    /// A live (pre-finalization) workout was interrupted. Rebuild the ViewModel
    /// from the checkpoint and let the user continue. `hasLiveSession` is true
    /// when the `HKWorkoutSession` was reconnected (live metrics resume); false
    /// is a constrained resume where HealthKit recording is lost but GymStreak
    /// history is fully preserved.
    case resumeLiveWorkout(hasLiveSession: Bool)
    /// Finalization had already begun (a frozen ticket-04 entry sits in a
    /// HealthKit phase). Resume ONLY the terminal finalization; never reopen
    /// editing or rebuild the payload.
    case resumeFinalization(hasLiveSession: Bool)
    /// The frozen entry already advanced past its HealthKit phase (finalization
    /// completed before the crash). Only stale checkpoint cleanup remains.
    case finalizationComplete
    /// HealthKit has an active session but the app checkpoint is missing or
    /// corrupt. Preserve the HealthKit workout without fabricating routine or
    /// template membership.
    case constrainedOrphanSession
}

/// Pure decision function for watch active-workout recovery. Every crash point
/// maps to exactly one decision from durable inputs; no HealthKit, no I/O.
enum WatchWorkoutRecoveryPlanner {
    /// - Parameters:
    ///   - hasCheckpoint: a valid app checkpoint was loaded.
    ///   - frozenEntryPhase: the phase of the durable outgoing entry keyed by
    ///     the workout under recovery, or nil when no entry exists (finalization
    ///     never began).
    ///   - didRecoverLiveSession: `recoverActiveWorkoutSession` returned a still
    ///     -active session that was reconnected.
    static func plan(
        hasCheckpoint: Bool,
        frozenEntryPhase: OutgoingWorkoutPhase?,
        didRecoverLiveSession: Bool
    ) -> WatchWorkoutRecoveryDecision {
        switch frozenEntryPhase {
        case .awaitingHealthKitMetadata, .awaitingHealthKitFinish:
            // Finalization began but did not finish the HealthKit save. An
            // active recovered session is NOT treated as proof the workout
            // ended — the finalizer re-runs the remaining HealthKit steps on the
            // recovered session (which also ends a still-running session so it
            // cannot leak and block the next workout), or, with no live session,
            // promotes the durable payload while external-UUID reconciliation
            // records whether Apple Health kept the record.
            return .resumeFinalization(hasLiveSession: didRecoverLiveSession)
        case .transportEligible, .quarantined:
            // Finalization already advanced past HealthKit before the crash;
            // only a stale checkpoint may remain.
            return hasCheckpoint ? .finalizationComplete : .none
        case nil:
            // No finalization entry → the workout was still live when it died.
            if hasCheckpoint {
                return .resumeLiveWorkout(hasLiveSession: didRecoverLiveSession)
            }
            return didRecoverLiveSession ? .constrainedOrphanSession : .none
        }
    }
}
