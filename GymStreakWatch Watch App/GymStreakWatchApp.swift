//
//  GymStreakWatchApp.swift
//  GymStreakWatch Watch App
//
//  Created by Julian Manke on 18.11.25.
//

import SwiftUI
import SwiftData

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
            // Fallback to local-only if no iCloud account
            print("Failed to create CloudKit container: \(error). Falling back to local storage.")
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
            NavigationStack {
                RoutineListView()
            }
            .environmentObject(workoutViewModel)
            .task {
                // Register workout view model for Action Button intents
                AppStateProvider.shared.setWorkoutViewModel(workoutViewModel)
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
