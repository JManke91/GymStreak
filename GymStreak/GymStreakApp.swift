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
    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-UI_TESTING")
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Routine.self,
            Exercise.self,
            RoutineExercise.self,
            ExerciseSet.self,
            WorkoutSession.self,
            WorkoutExercise.self,
            WorkoutSet.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
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
