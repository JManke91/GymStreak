import Foundation

// MARK: - Completed Workout for syncing back from Watch to iOS

struct CompletedWatchWorkout: Codable {
    let id: UUID
    let routineId: UUID
    let routineName: String
    let startTime: Date
    let endTime: Date
    let exercises: [CompletedWatchExercise]
    let shouldUpdateTemplate: Bool
    /// The UUID used as HKMetadataKeyExternalUUID when saving to HealthKit.
    /// Used to correlate SwiftData WorkoutSession with HealthKit workout.
    let healthKitWorkoutId: UUID?

    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    var hasModifiedSets: Bool {
        exercises.contains { exercise in
            exercise.sets.contains { set in
                set.actualReps != set.plannedReps || set.actualWeight != set.plannedWeight
            }
        }
    }

    var modifiedSetsCount: Int {
        exercises.reduce(0) { total, exercise in
            total + exercise.sets.filter { set in
                set.actualReps != set.plannedReps || set.actualWeight != set.plannedWeight
            }.count
        }
    }
}

struct CompletedWatchExercise: Codable {
    let id: UUID
    let name: String
    let muscleGroup: String
    let sets: [CompletedWatchSet]
    let order: Int
    let supersetId: UUID?
    let supersetOrder: Int
}

struct CompletedWatchSet: Codable {
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
