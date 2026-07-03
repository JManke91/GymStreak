//
//  ExerciseProgressProviding.swift
//  GymStreak
//
//  Protocol surface for exercise progress aggregation, extracted so
//  Presentation-layer Views/ViewModels can depend on an abstraction rather
//  than the `ExerciseProgressService` concrete Data-layer type directly.
//

import Foundation

/// Mirrors the subset of `ExerciseProgressService`'s public API consumed by
/// `ExerciseProgressViewModel`, `ExerciseProgressChartView`, `WorkoutDetailView`,
/// and `SaveWorkoutView`. See `ExerciseProgressService` for full documentation.
@MainActor
protocol ExerciseProgressProviding: AnyObject {

    /// Fetches progress data for a specific exercise within a timeframe.
    func fetchProgressData(
        for exerciseName: String,
        exerciseId: UUID?,
        timeframe: ChartTimeframe
    ) -> ExerciseProgressData

    /// Whether `name` is unique (case-insensitive) among the user's live `Exercise` library.
    func isLiveNameUnique(_ name: String) -> Bool

    /// Compares current workout exercises with their previous performances.
    func compareWithPrevious(workout: WorkoutSession) -> [ExerciseComparisonResult]
}
