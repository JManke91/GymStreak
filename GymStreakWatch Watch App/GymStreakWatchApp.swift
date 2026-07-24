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
            NavigationStack {
                RoutineListView()
            }
            .environmentObject(appState.routineStore)
            .environmentObject(appState.workoutViewModel)
            .environmentObject(appState.exerciseCatalogStore)
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

// MARK: - App State Container

@MainActor
final class AppState: ObservableObject {
    let routineStore: RoutineStore
    let healthKitManager: WatchHealthKitManager
    let workoutViewModel: WatchWorkoutViewModel
    /// Owned by WatchConnectivityManager (the delegate needs it during cold
    /// background wakes, before any UI exists); referenced here at init time
    /// so it is created — and its inbox drained — before views appear.
    let exerciseCatalogStore: ExerciseCatalogStore

    init() {
        let connectivity = WatchConnectivityManager.shared
        // Projection of the one sync-state owner — never a second copy of the
        // routines (ticket 05).
        let store = RoutineStore(syncState: connectivity.syncState)
        let healthKit = WatchHealthKitManager()

        self.routineStore = store
        self.healthKitManager = healthKit
        self.exerciseCatalogStore = connectivity.exerciseCatalogStore
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
            healthKitManager: healthKitManager
        )
        WatchWorkoutRecoveryCoordinator.shared.recoverIfNeeded()
        applicationDidBecomeActive()
    }

    func applicationDidBecomeActive() {
        WatchConnectivityManager.shared.transportEligibleWorkouts()
    }
}
