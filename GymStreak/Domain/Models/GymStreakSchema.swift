//
//  GymStreakSchema.swift
//  GymStreak
//

import SwiftData

/// Single source of truth for every SwiftData model type in the iOS app.
/// Used by the app's `ModelContainer` (GymStreakApp) and by the debug-only
/// CloudKit schema initializer — keep this list in sync with new @Model types
/// so both always operate on the identical schema.
enum GymStreakSchema {
    /// CloudKit container the private database syncs to. Must match the
    /// iCloud container in GymStreak.entitlements.
    static let cloudKitContainerIdentifier = "iCloud.com.jmanke.gymstreak"

    static let modelTypes: [any PersistentModel.Type] = [
        Routine.self,
        Exercise.self,
        RoutineExercise.self,
        ExerciseSet.self,
        RoutineExerciseAlternative.self,
        AlternativeExerciseSet.self,
        RoutineSchedule.self,
        WorkoutSession.self,
        WorkoutExercise.self,
        WorkoutSet.self
    ]
}
