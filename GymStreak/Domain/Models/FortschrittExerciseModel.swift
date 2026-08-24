//
//  FortschrittExerciseModel.swift
//  GymStreak
//

import Foundation

/// Immutable row values for the Fortschritt tab.
///
/// This lives in Domain because the Data-layer history actor produces it and Presentation consumes
/// it. It is an aggregate, not a DTO mirror of the SwiftData store.
struct FortschrittExerciseModel: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let primaryMuscleGroup: String
    let muscleGroups: [String]
    let exerciseId: UUID?
    let workoutCount: Int
    let lastPerformed: Date?
    let trendPct: Double?
    let sparkline: [Double]
    /// How many distinct usages this exercise's history holds — the same count the detail
    /// screen's picker offers. `1` (or `0` for an exercise with no history) means there is
    /// nothing to choose between and the row renders exactly as it did before usages
    /// existed.
    let usageCount: Int
    /// The usage `sparkline`, `trendPct` and `lastPerformed` describe, and the one the
    /// detail screen opens on when this row is tapped. `nil` while `usageCount <= 1`,
    /// where the single usage *is* the whole exercise.
    ///
    /// `workoutCount` deliberately stays the exercise's total — see
    /// `docs/progress-charts.md`.
    let headlineUsage: ExerciseUsagePickerItem?
    /// `true` when `sparkline` carries **assistance** rather than load: a counterweight
    /// exercise whose history has no body-mass snapshot to turn the entered kilograms into
    /// an effective weight. The series is inverted (less assistance reads as progress), so
    /// the row must name it as assistance — the same rule
    /// `ExerciseProgressViewModel.selectedMetricTitle` applies on the detail screen.
    let chartsAssistance: Bool

    init(
        id: String,
        name: String,
        primaryMuscleGroup: String,
        muscleGroups: [String],
        exerciseId: UUID?,
        workoutCount: Int,
        lastPerformed: Date?,
        trendPct: Double?,
        sparkline: [Double],
        usageCount: Int = 1,
        headlineUsage: ExerciseUsagePickerItem? = nil,
        chartsAssistance: Bool = false
    ) {
        self.id = id
        self.name = name
        self.primaryMuscleGroup = primaryMuscleGroup
        self.muscleGroups = muscleGroups
        self.exerciseId = exerciseId
        self.workoutCount = workoutCount
        self.lastPerformed = lastPerformed
        self.trendPct = trendPct
        self.sparkline = sparkline
        self.usageCount = usageCount
        self.headlineUsage = headlineUsage
        self.chartsAssistance = chartsAssistance
    }
}
