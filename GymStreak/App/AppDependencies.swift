//
//  AppDependencies.swift
//  GymStreak
//
//  Composition root: owns the repository and gateway instances used across
//  the app, built once from the shared ModelContainer's mainContext. Views
//  read this via `@EnvironmentObject` and pass dependencies down to the
//  ViewModels they construct — views themselves must never construct
//  repositories or services directly.
//

import Foundation
import SwiftData

@MainActor
final class AppDependencies: ObservableObject {
    let routineRepository: RoutineRepository
    let exerciseRepository: ExerciseRepository
    let workoutSessionRepository: WorkoutSessionRepository

    /// A true app-wide singleton — `WatchConnectivityManager.shared` must be the same
    /// instance everywhere so its WCSession delegate (registered at app launch) is the
    /// one that receives deliveries.
    let watchSync: WatchSyncServicing

    /// Shared across the app since it's bound to the container's stable mainContext —
    /// no need to reconstruct it per screen the way the old modelContext-swap pattern did.
    /// Exposed as `ExerciseProgressProviding` — Presentation depends on the protocol,
    /// this composition root is the only place allowed to know the concrete type.
    let exerciseProgressService: ExerciseProgressProviding

    /// Launch-time seeder for the built-in starter exercise catalog — seeds the
    /// catalog for all users (skipping name collisions with user-created
    /// exercises) and dedups CloudKit sync races (see
    /// docs/starter-exercise-library.md). Invoked once from GymStreakApp at launch.
    let defaultContentSeeder: DefaultContentSeeder

    init(modelContext: ModelContext) {
        self.routineRepository = SwiftDataRoutineRepository(modelContext: modelContext)
        self.exerciseRepository = SwiftDataExerciseRepository(modelContext: modelContext)
        self.workoutSessionRepository = SwiftDataWorkoutSessionRepository(modelContext: modelContext)
        self.watchSync = WatchConnectivityManager.shared
        self.exerciseProgressService = ExerciseProgressService(modelContext: modelContext)
        self.defaultContentSeeder = DefaultContentSeeder(modelContext: modelContext)
    }

    /// Each `WorkoutViewModel` owns its own HealthKit workout session — unlike
    /// WatchConnectivity there is no cross-instance state to share, and the previous
    /// code created a fresh `HealthKitWorkoutManager()` per WorkoutViewModel (there are
    /// two concurrently: one on the Routines tab for active workouts, one on the
    /// History tab). A factory preserves that instead of collapsing them into one.
    func makeHealthKitWorkoutService() -> HealthKitWorkoutServicing {
        HealthKitWorkoutManager()
    }
}
