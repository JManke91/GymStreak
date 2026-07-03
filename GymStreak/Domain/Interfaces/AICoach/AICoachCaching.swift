//
//  AICoachCaching.swift
//  GymStreak
//
//  Protocol surface for the AI Coach disk cache, extracted so Presentation-layer
//  ViewModels can depend on an abstraction rather than the `AICoachCache`
//  singleton directly (testability / DI).
//

import Foundation

/// Disk-backed cache surface for AI Coach narrative outputs.
///
/// Mirrors `AICoachCache`'s public API. See `AICoachCache` for details on the
/// three cache namespaces (post-workout, period recap, exercise deep-dive)
/// plus workout analysis, and their key formats.
@MainActor
protocol AICoachCaching: AnyObject {

    // MARK: - Post-Workout Recap

    func loadPostWorkout(workoutId: UUID) -> PostWorkoutRecapOutput?
    func savePostWorkout(workoutId: UUID, output: PostWorkoutRecapOutput)
    func invalidatePostWorkout(workoutId: UUID)

    // MARK: - Period Recap

    func loadPeriodRecap(key: String) -> PeriodRecapOutput?
    func savePeriodRecap(key: String, output: PeriodRecapOutput)
    func invalidatePeriodRecap(key: String)

    // MARK: - Exercise Deep-Dive

    func loadExerciseDeepDive(key: String) -> ExerciseDeepDiveOutput?
    func saveExerciseDeepDive(key: String, output: ExerciseDeepDiveOutput)
    func invalidateExerciseDeepDive(key: String)

    // MARK: - Workout Analysis

    func loadWorkoutAnalysis(workoutId: UUID) -> WorkoutAnalysisOutput?
    func saveWorkoutAnalysis(workoutId: UUID, output: WorkoutAnalysisOutput)
    func invalidateWorkoutAnalysis(workoutId: UUID)
}
