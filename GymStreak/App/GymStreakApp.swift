//
//  GymStreakApp.swift
//  GymStreak
//
//  Created by Julian Manke on 14.08.25.
//

import SwiftUI
import SwiftData

@main
struct GymStreakApp: App {
    // Initialize CloudSyncObserver early to catch all sync events
    @StateObject private var cloudSyncObserver = CloudSyncObserver.shared

    // Initialize WatchConnectivityManager early so the WCSession delegate is
    // registered before any queued userInfo (e.g. completed watch workouts)
    // can be delivered during launch. Activating from a lazily-initialized
    // view-scoped object is too late and can drop deliveries.
    @StateObject private var watchConnectivity = WatchConnectivityManager.shared

    // Composition root: built once from the shared ModelContainer's mainContext
    // and handed down to every view via the environment.
    @StateObject private var dependencies: AppDependencies

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-UI_TESTING")
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Routine.self,
            Exercise.self,
            RoutineExercise.self,
            ExerciseSet.self,
            RoutineExerciseAlternative.self,
            AlternativeExerciseSet.self,
            WorkoutSession.self,
            WorkoutExercise.self,
            WorkoutSet.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.jmanke.gymstreak")
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // If CloudKit container fails (e.g., no iCloud account), fall back to local-only storage
            print("Failed to create CloudKit container: \(error). Falling back to local storage.")
            let localConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            do {
                return try ModelContainer(for: schema, configurations: [localConfig])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    init() {
        let mainContext = sharedModelContainer.mainContext
        _dependencies = StateObject(wrappedValue: AppDependencies(modelContext: mainContext))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dependencies)
                .onAppear {
                    if isUITesting {
                        seedTestData()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }

    @MainActor
    private func seedTestData() {
        TestDataSeeder.seedData(modelContext: sharedModelContainer.mainContext)
    }
}
