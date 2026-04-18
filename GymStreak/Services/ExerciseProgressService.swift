//
//  ExerciseProgressService.swift
//  GymStreak
//

import Foundation
import SwiftData

/// Service for fetching and aggregating exercise progress data across workout sessions
@MainActor
class ExerciseProgressService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Progress Data for Charts

    /// Fetches progress data for a specific exercise within a timeframe
    /// - Parameters:
    ///   - exerciseName: The name of the exercise (case-insensitive match)
    ///   - timeframe: The timeframe to fetch data for
    /// - Returns: ExerciseProgressData containing all data points for charting
    func fetchProgressData(
        for exerciseName: String,
        timeframe: ChartTimeframe
    ) -> ExerciseProgressData {
        let startDate = timeframe.startDate
        let normalizedName = exerciseName.lowercased()

        // Fetch all completed workout sessions within the timeframe
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.startTime >= startDate && session.endTime != nil
            },
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )

        do {
            let sessions = try modelContext.fetch(descriptor)
            var dataPoints: [ExerciseProgressDataPoint] = []

            for session in sessions {
                // Find exercises matching the name (case-insensitive)
                let matchingExercises = session.workoutExercisesList.filter { exercise in
                    exercise.exerciseName.lowercased() == normalizedName
                }

                // Aggregate all matching exercises into a single data point per session
                var sessionMaxWeight: Double = 0
                var sessionTotalVolume: Double = 0
                var sessionTotalReps: Int = 0
                var sessionTotalSets: Int = 0
                var sessionBest1RM: Double = 0
                var hasCompletedSets = false

                for exercise in matchingExercises {
                    let completedSets = exercise.setsList.filter(\.isCompleted)
                    guard !completedSets.isEmpty else { continue }
                    hasCompletedSets = true

                    let usePlanned = exercise.progressiveOverloadApplied
                    let maxWeight = completedSets.map { usePlanned ? $0.plannedWeight : $0.actualWeight }.max() ?? 0
                    sessionMaxWeight = max(sessionMaxWeight, maxWeight)

                    sessionTotalVolume += completedSets.reduce(0) {
                        let w = usePlanned ? $1.plannedWeight : $1.actualWeight
                        let r = usePlanned ? $1.plannedReps : $1.actualReps
                        return $0 + (w * Double(r))
                    }
                    sessionTotalReps += completedSets.reduce(0) { $0 + (usePlanned ? $1.plannedReps : $1.actualReps) }
                    sessionTotalSets += completedSets.count

                    let estimated1RM = calculateEstimated1RM(from: completedSets, usePlannedValues: usePlanned)
                    sessionBest1RM = max(sessionBest1RM, estimated1RM)
                }

                guard hasCompletedSets else { continue }

                let dataPoint = ExerciseProgressDataPoint(
                    date: session.startTime,
                    maxWeight: sessionMaxWeight,
                    estimated1RM: sessionBest1RM,
                    totalVolume: sessionTotalVolume,
                    totalSets: sessionTotalSets,
                    totalReps: sessionTotalReps,
                    workoutSessionId: session.id
                )

                dataPoints.append(dataPoint)
            }

            return ExerciseProgressData(
                exerciseName: exerciseName,
                dataPoints: dataPoints
            )
        } catch {
            print("Error fetching progress data: \(error)")
            return ExerciseProgressData(exerciseName: exerciseName, dataPoints: [])
        }
    }

    // MARK: - Previous Performance Lookup

    /// Finds the previous time an exercise was performed before a given date
    /// - Parameters:
    ///   - exerciseName: The name of the exercise (case-insensitive match)
    ///   - date: The date to look before
    /// - Returns: PreviousExercisePerformance if found, nil otherwise
    func previousPerformance(
        for exerciseName: String,
        before date: Date
    ) -> PreviousExercisePerformance? {
        let normalizedName = exerciseName.lowercased()

        // Fetch completed sessions before the given date, most recent first
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.startTime < date && session.endTime != nil
            },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )

        do {
            let sessions = try modelContext.fetch(descriptor)

            // Find the most recent session that contains this exercise
            for session in sessions {
                let matchingExercise = session.workoutExercisesList.first { exercise in
                    exercise.exerciseName.lowercased() == normalizedName
                }

                guard let exercise = matchingExercise else { continue }

                let usePlanned = exercise.progressiveOverloadApplied
                let sets = exercise.setsList.sorted(by: { $0.order < $1.order }).map { set in
                    PreviousExercisePerformance.SetPerformance(
                        reps: usePlanned ? set.plannedReps : set.actualReps,
                        weight: usePlanned ? set.plannedWeight : set.actualWeight,
                        isCompleted: set.isCompleted
                    )
                }

                return PreviousExercisePerformance(
                    date: session.startTime,
                    routineName: session.routineName,
                    sets: sets
                )
            }

            return nil
        } catch {
            print("Error fetching previous performance: \(error)")
            return nil
        }
    }

    // MARK: - Comparison for Workout Detail View

    /// Compares current workout exercises with their previous performances
    /// - Parameter workout: The current workout session to compare
    /// - Returns: Array of comparison results for each exercise
    func compareWithPrevious(workout: WorkoutSession) -> [ExerciseComparisonResult] {
        var results: [ExerciseComparisonResult] = []

        for exercise in workout.workoutExercisesList.sorted(by: { $0.order < $1.order }) {
            let previous = previousPerformance(for: exercise.exerciseName, before: workout.startTime)

            let completedSets = exercise.setsList.filter(\.isCompleted)
            let sortedSets = exercise.setsList.sorted(by: { $0.order < $1.order })
            let usePlanned = exercise.progressiveOverloadApplied

            // Build set comparisons
            var setComparisons: [ExerciseComparisonResult.CurrentExercisePerformance.SetComparison] = []

            for (index, set) in sortedSets.enumerated() {
                // Get corresponding previous set if available
                let previousSet = previous?.sets.indices.contains(index) == true ? previous?.sets[index] : nil

                let reps = usePlanned ? set.plannedReps : set.actualReps
                let weight = usePlanned ? set.plannedWeight : set.actualWeight

                let comparison = ExerciseComparisonResult.CurrentExercisePerformance.SetComparison(
                    setNumber: index + 1,
                    currentReps: reps,
                    currentWeight: weight,
                    previousReps: previousSet?.reps,
                    previousWeight: previousSet?.weight,
                    isCompleted: set.isCompleted
                )
                setComparisons.append(comparison)
            }

            let totalVolume = completedSets.reduce(0.0) { subtotal, set in
                let w = usePlanned ? set.plannedWeight : set.actualWeight
                let r = usePlanned ? set.plannedReps : set.actualReps
                return subtotal + (w * Double(r))
            }
            let totalReps = completedSets.reduce(0) { $0 + (usePlanned ? $1.plannedReps : $1.actualReps) }

            let currentPerformance = ExerciseComparisonResult.CurrentExercisePerformance(
                sets: setComparisons,
                totalVolume: totalVolume,
                completedSetsCount: completedSets.count,
                totalReps: totalReps
            )

            let result = ExerciseComparisonResult(
                exerciseName: exercise.exerciseName,
                currentPerformance: currentPerformance,
                previousPerformance: previous
            )

            results.append(result)
        }

        return results
    }

    // MARK: - Private Helpers

    /// Calculates estimated 1RM using Epley formula
    /// Uses the best set (highest estimated 1RM) from the given sets
    private func calculateEstimated1RM(from sets: [WorkoutSet], usePlannedValues: Bool = false) -> Double {
        guard !sets.isEmpty else { return 0 }

        var best1RM: Double = 0

        for set in sets {
            let weight = usePlannedValues ? set.plannedWeight : set.actualWeight
            let reps = usePlannedValues ? set.plannedReps : set.actualReps
            guard set.isCompleted, weight > 0 else { continue }

            // Epley formula: weight * (1 + reps/30)
            let estimated = weight * (1 + Double(reps) / 30.0)
            best1RM = max(best1RM, estimated)
        }

        return best1RM
    }
}
