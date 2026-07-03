//
//  ExerciseProgressListView.swift
//  GymStreak
//
//  Only hosts the ExerciseWithHistory value type used by the new History redesign's
//  navigation destination. The former list view was replaced by FortschrittTabView.
//

import Foundation

/// Lightweight payload used to push the exercise detail (ExerciseProgressChartView)
/// onto the navigation stack. Built from the FortschrittExerciseModel at navigation time.
struct ExerciseWithHistory: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let muscleGroups: [String]
    let exerciseId: UUID?
    let workoutCount: Int
    let lastPerformed: Date?
    var allExercises: [ExerciseWithHistory] = []

    var primaryMuscleGroup: String {
        muscleGroups.first ?? "General"
    }

    /// Stable key matching WorkoutExercise.stableKey for filtering across sessions.
    var stableKey: String {
        exerciseId?.uuidString ?? name.lowercased()
    }

    // Hashable — exclude allExercises to avoid circular reference
    func hash(into hasher: inout Hasher) {
        hasher.combine(stableKey)
    }

    static func == (lhs: ExerciseWithHistory, rhs: ExerciseWithHistory) -> Bool {
        lhs.stableKey == rhs.stableKey
    }
}
