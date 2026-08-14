//
//  ExerciseProgressProviding.swift
//  GymStreak
//
//  Protocol surface for exercise-vs-previous comparison, extracted so
//  Presentation-layer Views/ViewModels can depend on an abstraction rather
//  than the `ExerciseProgressService` concrete Data-layer type directly.
//

import Foundation

/// Mirrors the subset of `ExerciseProgressService`'s API consumed by
/// `WorkoutDetailView` and `SaveWorkoutView`. See `ExerciseProgressService` for full
/// documentation.
///
/// `@MainActor` because `compareWithPrevious` takes a main-context `WorkoutSession` and
/// walks its relationships. The exercise **chart** deliberately does not come through
/// here — it reads `HistorySnapshotProviding`, whose model actor keeps that traversal
/// off the main actor (audit P1.2).
@MainActor
protocol ExerciseProgressProviding: AnyObject {

    /// Compares current workout exercises with their previous performances.
    func compareWithPrevious(workout: WorkoutSession) -> [ExerciseComparisonResult]
}
