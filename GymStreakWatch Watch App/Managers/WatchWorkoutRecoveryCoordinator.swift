//
//  WatchWorkoutRecoveryCoordinator.swift
//  GymStreakWatch Watch App
//
//  Ticket 08 (in-workout routine editing): orchestrates recovery of an active
//  watch workout after watchOS terminated and relaunched GymStreak mid-session.
//  Runs the actual recovery exactly ONCE per process.
//
//  Flow: load the app checkpoint, ask HealthKit for any still-active session
//  (reconnecting it), then execute the pure `WatchWorkoutRecoveryPlanner`
//  decision against the ViewModel / HealthKit manager / durable sync-state
//  owner. Any OTHER entries a previous process stranded mid-HealthKit are then
//  promoted — this is where ticket 08 takes over the launch-time promotion that
//  `WatchSyncStateStore.promoteInterruptedFinalizations` used to do eagerly in
//  `WatchConnectivityManager.init` (which would have preempted live recovery).
//
//  Reachable before any UI via `.shared` (the `WKApplicationDelegate` recovery
//  callback can fire cold). `AppState` registers the live ViewModel + HealthKit
//  manager once they exist; a recovery request that arrives earlier is buffered
//  and runs on registration.
//

import Foundation
import HealthKit

@MainActor
final class WatchWorkoutRecoveryCoordinator {
    static let shared = WatchWorkoutRecoveryCoordinator()

    private weak var viewModel: WatchWorkoutViewModel?
    private weak var healthKitManager: WatchHealthKitManager?
    private weak var conditioningRun: WatchConditioningRunViewModel?
    private weak var conditioningWorkout: WatchConditioningWorkoutManager?
    private weak var matSession: WatchMatSessionViewModel?
    private weak var matWorkout: WatchConditioningWorkoutManager?
    private let conditioningCheckpoints = WatchConditioningCheckpointStore()
    private let matCheckpoints = WatchMatSessionCheckpointStore()
    private let checkpointStore = WatchActiveWorkoutCheckpointStore()
    private var syncState: WatchSyncStateStore { WatchConnectivityManager.shared.syncState }

    private var hasAttempted = false
    private var isRecovering = false
    private var pendingRequest = false

    private init() {}

    /// Called by `AppState` once the live components exist. Runs any buffered
    /// recovery request.
    func register(
        viewModel: WatchWorkoutViewModel,
        healthKitManager: WatchHealthKitManager,
        conditioningRun: WatchConditioningRunViewModel,
        conditioningWorkout: WatchConditioningWorkoutManager,
        matSession: WatchMatSessionViewModel,
        matWorkout: WatchConditioningWorkoutManager
    ) {
        self.viewModel = viewModel
        self.healthKitManager = healthKitManager
        self.conditioningRun = conditioningRun
        self.conditioningWorkout = conditioningWorkout
        self.matSession = matSession
        self.matWorkout = matWorkout
        if pendingRequest { recoverIfNeeded() }
    }

    /// Idempotent recovery entry point. Safe to call from the app-delegate
    /// recovery callback, `applicationDidFinishLaunching`, and `AppState`
    /// registration; performs the actual recovery exactly once per process. If
    /// the live components are not registered yet, the request is buffered and
    /// runs on `register`.
    func recoverIfNeeded() {
        guard !ProcessInfo.processInfo.arguments.contains("-UI_TESTING") else { return }
        guard !hasAttempted, !isRecovering else { return }
        guard let viewModel, let healthKitManager else {
            pendingRequest = true
            return
        }
        hasAttempted = true
        isRecovering = true
        Task {
            await performRecovery(viewModel: viewModel, healthKit: healthKitManager)
            isRecovering = false
        }
    }

    /// Resumes a conditioning session left running by a previous process, or
    /// discards its stale checkpoint cleanly. Returns whether `recovered` was taken.
    ///
    /// Told apart from strength and mat sessions by the recovered session's activity
    /// type, which must be the checkpoint modality's — HealthKit restores the
    /// original configuration. No live session means the workout was
    /// ended or never began; its checkpoint has nothing left to resume.
    private func resumeConditioning(_ recovered: HKWorkoutSession?) -> Bool {
        guard let checkpoint = conditioningCheckpoints.load() else { return false }
        // The checkpoint modality's own activity type — never strength, and never a
        // mat session whose own checkpoint write failed.
        let activityType = WatchConditioningWorkoutManager.configuration(for: checkpoint.modality).activityType
        guard let recovered,
              recovered.workoutConfiguration.activityType == activityType,
              let conditioningRun, let conditioningWorkout else {
            conditioningCheckpoints.clear()
            print("WatchWorkoutRecovery: stale conditioning checkpoint discarded")
            return false
        }
        conditioningWorkout.adopt(recovered)
        conditioningRun.resumeRecovered(from: checkpoint)
        print("WatchWorkoutRecovery: conditioning session resumed")
        return true
    }

    /// The same for a mat session (positioning ticket 05), its own checkpoint file.
    /// Runs before the conditioning check and claims only a session with the sport's
    /// own activity type, so a stale checkpoint of one kind never adopts the other's.
    private func resumeMatSession(_ recovered: HKWorkoutSession?) -> Bool {
        guard let checkpoint = matCheckpoints.load() else { return false }
        let activityType = WatchConditioningWorkoutManager
            .configuration(forSport: checkpoint.sport.rawValue).activityType
        guard let recovered,
              recovered.workoutConfiguration.activityType == activityType,
              let matSession, let matWorkout else {
            matCheckpoints.clear()
            print("WatchWorkoutRecovery: stale mat-session checkpoint discarded")
            return false
        }
        matWorkout.adopt(recovered)
        matSession.resumeRecovered(from: checkpoint)
        print("WatchWorkoutRecovery: mat session resumed")
        return true
    }

    private func performRecovery(
        viewModel: WatchWorkoutViewModel,
        healthKit: WatchHealthKitManager
    ) async {
        let checkpoint = checkpointStore.load()

        // The workout under recovery: the checkpoint's, else the oldest durable
        // entry a previous process left mid-HealthKit finalization.
        let workoutID = checkpoint?.workoutID ?? syncState.interruptedFinalizationWorkoutIDs().first
        let frozenPhase = workoutID.flatMap { syncState.entry(id: $0)?.phase }

        // Reconnect the live HealthKit session if one is still active.
        var recovered = await healthKit.recoverActiveSession()
        // A mat or conditioning session (positioning 05, ticket 06) is recovered first and entirely on its
        // own path: it has no strength checkpoint and no queue entry, so the planner
        // below would otherwise finish it as an orphan.
        if resumeMatSession(recovered) || resumeConditioning(recovered) { recovered = nil }

        var didRecoverLive = false
        if let session = recovered {
            let start = checkpoint?.startTime ?? session.startDate ?? Date()
            didRecoverLive = healthKit.adoptRecoveredSession(session, startDate: start)
        }

        let decision = WatchWorkoutRecoveryPlanner.plan(
            hasCheckpoint: checkpoint != nil,
            frozenEntryPhase: frozenPhase,
            didRecoverLiveSession: didRecoverLive
        )
        print("WatchWorkoutRecovery: decision=\(decision) checkpoint=\(checkpoint != nil) phase=\(String(describing: frozenPhase)) live=\(didRecoverLive)")

        switch decision {
        case .none:
            break
        case .resumeLiveWorkout(let hasLive):
            if let checkpoint {
                viewModel.resumeRecoveredWorkout(from: checkpoint, hasLiveSession: hasLive)
            }
        case .resumeFinalization(let hasLive):
            // Diagnostic only: whether Apple Health already kept the record.
            if !hasLive, let workoutID,
               let externalUUID = syncState.entry(id: workoutID)?.completedWorkout?.healthKitWorkoutId {
                let saved = await healthKit.savedWorkoutExists(externalUUID: externalUUID)
                print("WatchWorkoutRecovery: finalization resume, HealthKit already saved=\(saved)")
            }
            if let workoutID {
                await viewModel.resumeInterruptedFinalization(workoutID: workoutID)
            }
        case .finalizationComplete:
            checkpointStore.clear()
        case .constrainedOrphanSession:
            // Adopted an active session with no app checkpoint — preserve it in
            // Apple Health without fabricating routine/template membership.
            await healthKit.finishOrphanRecoveredSession()
        }

        // Sweep any OTHER entries a previous process stranded mid-HealthKit (the
        // system allows only one active session, so these can never have a live
        // session to finish) and drain transport.
        syncState.promoteInterruptedFinalizations()
        WatchConnectivityManager.shared.transportEligibleWorkouts()
    }
}
