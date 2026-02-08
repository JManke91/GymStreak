//
//  DefaultExerciseSeeder.swift
//  GymStreak
//
//  Seeds default exercises on first app launch
//

import Foundation
import SwiftData

@MainActor
class DefaultExerciseSeeder {
    private static let hasSeededExercisesKey = "hasSeededDefaultExercises"

    /// Seeds default exercises if this is the first launch
    static func seedIfNeeded(modelContext: ModelContext) {
        // Check if we've already seeded
        let hasSeeded = UserDefaults.standard.bool(forKey: hasSeededExercisesKey)
        guard !hasSeeded else { return }

        // Check if there are already exercises in the database
        let descriptor = FetchDescriptor<Exercise>()
        let existingExercises = (try? modelContext.fetch(descriptor)) ?? []
        guard existingExercises.isEmpty else {
            // Mark as seeded since user already has exercises
            UserDefaults.standard.set(true, forKey: hasSeededExercisesKey)
            return
        }

        // Seed the default exercises
        seedDefaultExercises(modelContext: modelContext)

        // Mark as seeded
        UserDefaults.standard.set(true, forKey: hasSeededExercisesKey)
    }

    private static func seedDefaultExercises(modelContext: ModelContext) {
        // Default exercises with their muscle groups
        let defaultExercises: [(name: String, muscleGroups: [String])] = [
            // Requested exercises
            ("Chest Press", ["Chest", "Triceps"]),
            ("Biceps Curls", ["Biceps"]),
            ("Incline Flying Dumbbells", ["Upper Chest"]),
            ("Shoulder Press Dumbbell", ["Shoulders", "Triceps"]),
            ("Skull Crusher Barbell", ["Triceps"]),
            ("Cable Triceps", ["Triceps"]),
            ("Dips", ["Triceps", "Chest"]),

            // Additional common exercises
            ("Bench Press", ["Chest", "Triceps", "Front Delts"]),
            ("Deadlift", ["Lower Back", "Hamstrings", "Glutes"]),
            ("Squat", ["Quadriceps", "Glutes", "Hamstrings"]),
            ("Pull-ups", ["Lats", "Biceps", "Upper Back"]),
            ("Barbell Rows", ["Upper Back", "Lats", "Biceps"]),
            ("Lateral Raises", ["Side Delts"]),
            ("Leg Press", ["Quadriceps", "Glutes"]),
            ("Leg Curls", ["Hamstrings"]),
            ("Calf Raises", ["Calves"]),
            ("Plank", ["Abs", "Obliques"]),
            ("Romanian Deadlift", ["Hamstrings", "Glutes", "Lower Back"])
        ]

        for exerciseData in defaultExercises {
            let exercise = Exercise(
                name: exerciseData.name,
                muscleGroups: exerciseData.muscleGroups
            )
            modelContext.insert(exercise)
        }

        do {
            try modelContext.save()
            print("DefaultExerciseSeeder: Seeded \(defaultExercises.count) default exercises")
        } catch {
            print("DefaultExerciseSeeder: Failed to seed exercises: \(error)")
        }
    }
}
