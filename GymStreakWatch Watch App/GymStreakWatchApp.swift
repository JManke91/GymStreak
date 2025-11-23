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
            .task {
                appState.connectServices()
            }
        }
    }
}

// MARK: - App State Container

@MainActor
final class AppState: ObservableObject {
    let routineStore: RoutineStore
    let healthKitManager: WatchHealthKitManager
    let workoutViewModel: WatchWorkoutViewModel

    init() {
        let store = RoutineStore()
        let healthKit = WatchHealthKitManager()
        let connectivity = WatchConnectivityManager.shared

        self.routineStore = store
        self.healthKitManager = healthKit
        self.workoutViewModel = WatchWorkoutViewModel(
            healthKitManager: healthKit,
            connectivityManager: connectivity
        )
    }

    func connectServices() {
        WatchConnectivityManager.shared.setRoutineStore(routineStore)
        // Register workout view model for Action Button intents
        AppStateProvider.shared.setWorkoutViewModel(workoutViewModel)
    }
}
