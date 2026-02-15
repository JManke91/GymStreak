//
//  GymStreakWatchApp.swift
//  GymStreakWatch Watch App
//
//  Created by Julian Manke on 18.11.25.
//

import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: "com.jmanke.gymstreak.watch", category: "App")

@main
struct GymStreakWatchApp: App {
    // MARK: - State Objects

    @StateObject private var cloudSyncObserver = CloudSyncObserver.shared
    @StateObject private var workoutViewModel: WatchWorkoutViewModel

    let sharedModelContainer: ModelContainer

    init() {
        let schema = Schema([
            Routine.self,
            Exercise.self,
            RoutineExercise.self,
            ExerciseSet.self,
            WorkoutSession.self,
            WorkoutExercise.self,
            WorkoutSet.self
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.jmanke.gymstreak")
        )

        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            logger.error("Failed to create CloudKit container: \(error.localizedDescription). Falling back to local storage.")
            let localConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            do {
                container = try ModelContainer(for: schema, configurations: [localConfig])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }

        self.sharedModelContainer = container

        let vm = WatchWorkoutViewModel(
            healthKitManager: WatchHealthKitManager(),
            connectivityManager: WatchConnectivityManager.shared,
            modelContext: container.mainContext
        )
        _workoutViewModel = StateObject(wrappedValue: vm)
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            WatchRootView(sharedModelContainer: sharedModelContainer)
                .environmentObject(workoutViewModel)
                .task {
                    // Register workout view model for Action Button intents
                    AppStateProvider.shared.setWorkoutViewModel(workoutViewModel)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

// MARK: - Root View

/// Wrapper view that observes `scenePhase` to nudge CloudKit sync when the app becomes active.
/// This handles cases where silent push notifications were missed (e.g., watch was offline).
private struct WatchRootView: View {
    @Environment(\.scenePhase) private var scenePhase

    let sharedModelContainer: ModelContainer

    var body: some View {
        NavigationStack {
            RoutineListView()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                logger.debug("App became active — nudging CloudKit sync")
                var descriptor = FetchDescriptor<Routine>()
                descriptor.fetchLimit = 1
                _ = try? sharedModelContainer.mainContext.fetch(descriptor)
            }
        }
    }
}
