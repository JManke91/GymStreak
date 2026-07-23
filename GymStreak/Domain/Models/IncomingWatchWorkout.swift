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

    // Template-transaction ordering identity (ticket 05); nil on no-template
    // workouts and on payloads from pre-ticket-05 watch builds.
    var templateTransactionID: UUID? = nil
    var templateSenderEpoch: UUID? = nil
    var templateSequence: UInt64? = nil

    // Explicit structural membership intent (ticket 07). The Data→Domain mapper
    // normalizes an absent wire array to empty, so a legacy/set-only payload is
    // simply "no structural intent". Minted slot IDs the watch added during the
    // workout (in final exercise order) and known slot IDs it removed (in
    // workout-start baseline order).
    var addedRoutineExerciseIDs: [UUID] = []
    var removedRoutineExerciseIDs: [UUID] = []

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
    /// Stable seeded-library fallback identity (ticket 07); nil when empty.
    /// Defaulted so pre-ticket-07 fixtures/constructions stay source-compatible;
    /// the Data→Domain mapper always supplies it from the wire model.
    var exerciseSeedKey: String? = nil
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
