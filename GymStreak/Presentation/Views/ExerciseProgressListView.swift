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
    /// Set only when another library exercise carries the same display name — see
    /// `FortschrittExerciseModel.equipmentQualifier`, which is where it is resolved.
    /// Carried through so the exercise switcher can tell two same-named entries apart
    /// without scanning the library itself.
    var equipmentQualifier: EquipmentType?
    /// The usage the Fortschritt row summarised, handed down so the detail screen opens
    /// on the same one — a row whose sparkline describes the most-trained usage must not
    /// push a screen that opens on a different one. `nil` when the exercise has a single
    /// usage (the screen's own default is then identical) or when the push came from
    /// somewhere without a row behind it.
    var initialUsage: ExerciseUsage.Key?
    var allExercises: [ExerciseWithHistory] = []

    var primaryMuscleGroup: String {
        muscleGroups.first ?? "General"
    }

    /// The name as the switcher prints it: qualified with the equipment only where the
    /// name is shared with another library exercise.
    var displayName: String {
        guard let equipmentQualifier else { return name }
        return "progress.exercise.with_equipment".localized(name, equipmentQualifier.displayName)
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
