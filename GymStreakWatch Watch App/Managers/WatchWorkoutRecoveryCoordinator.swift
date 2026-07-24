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
    private let checkpointStore = WatchActiveWorkoutCheckpointStore()
    private var syncState: WatchSyncStateStore { WatchConnectivityManager.shared.syncState }

    private var hasAttempted = false
    private var isRecovering = false
    private var pendingRequest = false

    private init() {}

    /// Called by `AppState` once the live components exist. Runs any buffered
    /// recovery request.
    func register(viewModel: WatchWorkoutViewModel, healthKitManager: WatchHealthKitManager) {
        self.viewModel = viewModel
        self.healthKitManager = healthKitManager
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
        var didRecoverLive = false
        if let session = await healthKit.recoverActiveSession() {
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
