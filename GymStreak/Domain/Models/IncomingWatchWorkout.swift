//
//  IncomingWatchWorkout.swift
//  GymStreak
//
//  Domain-facing representation of a completed workout received from the watch,
//  ready to be materialized into a `WorkoutSession` by
//  `WatchWorkoutIngestionService`. It deliberately mirrors the WatchConnectivity
//  wire DTO (`CompletedWatchWorkout` in `Data/Sync/WatchModels.swift`) so the
//  Domain layer never references the Codable sync type: the Data layer maps the
//  decoded wire DTO into this model at the WatchConnectivity boundary
//  (`CompletedWatchWorkout.toIncomingWatchWorkout()`). Keeping the two types
//  separate lets the on-the-wire format evolve independently of the domain
//  ingestion contract.
//

import Foundation

struct IncomingWatchWorkout {
    let id: UUID
    let routineId: UUID
    let routineName: String
    let startTime: Date
    let endTime: Date
    let exercises: [IncomingWatchExercise]
    let shouldUpdateTemplate: Bool
    /// The UUID used as `HKMetadataKeyExternalUUID` when the watch saved to
    /// HealthKit. Correlates the SwiftData `WorkoutSession` with the HK workout.
    let healthKitWorkoutId: UUID?

    var modifiedSetsCount: Int {
        exercises.reduce(0) { total, exercise in
            total + exercise.sets.filter { $0.actualReps != $0.plannedReps || $0.actualWeight != $0.plannedWeight }.count
        }
    }
}

struct IncomingWatchExercise {
    let id: UUID
    let name: String
    let muscleGroup: String
    let sets: [IncomingWatchSet]
    let order: Int
    let supersetId: UUID?
    let supersetOrder: Int
    let targetRepMin: Int?
    let targetRepMax: Int?
    let exerciseId: UUID?
    let loadBehaviorRaw: String
    /// Set only when the exercise was swapped for an alternative during the
    /// workout; `name`/`exerciseId` describe what was actually performed.
    let plannedExerciseId: UUID?
    let plannedExerciseName: String?
}

struct IncomingWatchSet {
    let id: UUID
    let plannedReps: Int
    let actualReps: Int
    let plannedWeight: Double
    let actualWeight: Double
    let restTime: TimeInterval
    let isCompleted: Bool
    let completedAt: Date?
    let order: Int
}
