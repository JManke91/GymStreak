//
//  GymStreakWatchApp.swift
//  GymStreakWatch Watch App
//
//  Created by Julian Manke on 18.11.25.
//

import SwiftUI
import Combine

@main
struct GymStreakWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase

    /// Ticket 08: the modern SwiftUI-lifecycle delegate that receives watchOS's
    /// `handleActiveWorkoutRecovery()` crash-relaunch callback.
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate

    // MARK: - State Objects

    @StateObject private var appState = AppState()

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            RootView(weightUnitStore: appState.weightUnitStore)
                .environmentObject(appState.routineStore)
                .environmentObject(appState.workoutViewModel)
                .environmentObject(appState.exerciseCatalogStore)
                .environment(appState.conditioningStore)
                .environment(appState.conditioningRun)
                .task {
                    appState.connectServices()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        appState.applicationDidBecomeActive()
                    }
                }
        }
        // Cold/background WatchConnectivity deliveries (e.g. catalogue file
        // transfers) wake the app without any UI. Keep the task alive until
        // the session queue is empty and the inbox drain has persisted.
        .backgroundTask(.watchConnectivity) {
            await WatchConnectivityManager.shared.handleWatchConnectivityBackgroundWake()
        }
    }
}

// MARK: - Root

/// Exists so the weight unit can be *observed* here rather than read once off
/// `AppState`: `AppState` is an `ObservableObject` holding another one, and a
/// change inside `WatchWeightUnitStore` does not invalidate its owner. Without
/// this view, switching the unit on iPhone would only reach the watch UI at the
/// next unrelated re-render.
private struct RootView: View {
    @ObservedObject var weightUnitStore: WatchWeightUnitStore
    @Environment(WatchConditioningRunViewModel.self) private var conditioningRun

    var body: some View {
        NavigationStack {
            RoutineListView()
        }
        // The conditioning runner (docs/fight-conditioning.md, ticket 06), above the
        // stack because a session starts from a pushed detail screen. Not
        // swipe-dismissable: it closes through its own Done once the session is over.
        .fullScreenCover(
            isPresented: Bindable(conditioningRun).isRunnerPresented,
            onDismiss: { conditioningRun.runnerDidDismiss() }
        ) {
            ConditioningRunnerView()
                .interactiveDismissDisabled()
        }
        // One injection point for the surfaces that render a weight. Modelled
        // on the iOS root: views read `\.weightUnit` directly rather than every
        // row initializer prop-drilling it.
        .environment(\.weightUnit, weightUnitStore.unit)
    }
}

// MARK: - App State Container

@MainActor
final class AppState: ObservableObject {
    let routineStore: RoutineStore
    /// Republished into the environment by `RootView`, so a unit change sent
    /// from the iPhone re-renders every weight on screen.
    let weightUnitStore: WatchWeightUnitStore
    let healthKitManager: WatchHealthKitManager
    let workoutViewModel: WatchWorkoutViewModel
    /// Owned by WatchConnectivityManager (the delegate needs it during cold
    /// background wakes, before any UI exists); referenced here at init time
    /// so it is created — and its inbox drained — before views appear.
    let exerciseCatalogStore: ExerciseCatalogStore
    /// The conditioning offer synced from the iPhone and the one runner that plays it
    /// (docs/fight-conditioning.md, ticket 06). The store is owned by the connectivity
    /// manager, like the catalogue.
    let conditioningStore: WatchConditioningStore
    let conditioningWorkout: WatchConditioningWorkoutManager
    let conditioningRun: WatchConditioningRunViewModel

    init() {
        let connectivity = WatchConnectivityManager.shared
        // Projection of the one sync-state owner — never a second copy of the
        // routines (ticket 05).
        let store = RoutineStore(syncState: connectivity.syncState)
        let healthKit = WatchHealthKitManager()

        self.routineStore = store
        self.weightUnitStore = WatchWeightUnitStore(syncState: connectivity.syncState)
        self.healthKitManager = healthKit
        self.exerciseCatalogStore = connectivity.exerciseCatalogStore
        self.conditioningStore = connectivity.conditioningStore
        let conditioningWorkout = WatchConditioningWorkoutManager()
        self.conditioningWorkout = conditioningWorkout
        self.conditioningRun = WatchConditioningRunViewModel(
            workout: conditioningWorkout,
            checkpoints: WatchConditioningCheckpointStore(),
            outbox: connectivity.conditioningOutbox,
            // `isWorkoutActive` turns false once the strength session reaches `.ended`.
            isOtherWorkoutActive: { [weak healthKit] in healthKit?.isWorkoutActive ?? false }
        )
        self.workoutViewModel = WatchWorkoutViewModel(
            healthKitManager: healthKit,
            connectivityManager: connectivity,
            routineStore: store
        )
    }

    func connectServices() {
        if ProcessInfo.processInfo.arguments.contains("-UI_TESTING") {
            routineStore.updateRoutines(WatchTestDataSeeder.sampleRoutines())
        }
        // Register workout view model for Action Button intents
        AppStateProvider.shared.setWorkoutViewModel(workoutViewModel)
        // Ticket 08: register the live components with the recovery coordinator
        // (which may already hold a buffered recovery request from the app
        // delegate) and attempt active-workout recovery on this launch.
        WatchWorkoutRecoveryCoordinator.shared.register(
            viewModel: workoutViewModel,
            healthKitManager: healthKitManager,
            conditioningRun: conditioningRun,
            conditioningWorkout: conditioningWorkout
        )
        WatchWorkoutRecoveryCoordinator.shared.recoverIfNeeded()
        applicationDidBecomeActive()
    }

    func applicationDidBecomeActive() {
        WatchConnectivityManager.shared.transportEligibleWorkouts()
        // "Today" and the program week roll over by the clock (ticket 06).
        conditioningStore.refresh()
    }
}
