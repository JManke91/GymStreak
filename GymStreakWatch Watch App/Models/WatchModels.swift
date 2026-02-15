import Foundation
import SwiftData

// MARK: - Active Workout State Models

struct ActiveWorkoutExercise: Identifiable {
    let id: UUID
    let name: String
    let muscleGroup: String
    var sets: [ActiveWorkoutSet]
    let order: Int
    let supersetId: UUID?
    let supersetOrder: Int

    var completedSetsCount: Int {
        sets.filter(\.isCompleted).count
    }

    var isComplete: Bool {
        sets.allSatisfy(\.isCompleted)
    }

    var isInSuperset: Bool {
        supersetId != nil
    }
}

struct ActiveWorkoutSet: Identifiable {
    let id: UUID
    var plannedReps: Int
    var actualReps: Int
    var plannedWeight: Double
    var actualWeight: Double
    var restTime: TimeInterval
    var isCompleted: Bool {
        return !(completedAt == nil)
    }
    var completedAt: Date?
    let order: Int

    var wasModified: Bool {
        actualReps != plannedReps || actualWeight != plannedWeight
    }
}

// MARK: - Workout Summary (shown after completing a workout on watch)

struct WatchWorkoutSummary {
    let routineName: String
    let duration: TimeInterval
    let completedSets: Int
    let totalSets: Int
    let completionPercentage: Int
    let activeCalories: Int?
    let exercises: [ExerciseSummary]

    struct ExerciseSummary: Identifiable {
        let id: UUID
        let name: String
        let muscleGroup: String
        let completedSets: Int
        let totalSets: Int
        let isComplete: Bool
    }

    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Completed Workout for syncing back to iOS

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

// MARK: - Conversion Extensions

extension RoutineExercise {
    func toActiveWorkoutExercise() -> ActiveWorkoutExercise {
        ActiveWorkoutExercise(
            id: id,
            name: exercise?.name ?? "Unknown",
            muscleGroup: exercise?.primaryMuscleGroup ?? "General",
            sets: setsList.sorted(by: { $0.order < $1.order }).enumerated().map { index, set in
                ActiveWorkoutSet(
                    id: set.id,
                    plannedReps: set.reps,
                    actualReps: set.reps,
                    plannedWeight: set.weight,
                    actualWeight: set.weight,
                    restTime: set.restTime,
                    completedAt: nil,
                    order: index
                )
            },
            order: order,
            supersetId: supersetId,
            supersetOrder: supersetOrder
        )
    }
}

extension ActiveWorkoutExercise {
    func toCompletedExercise() -> CompletedWatchExercise {
        CompletedWatchExercise(
            id: id,
            name: name,
            muscleGroup: muscleGroup,
            sets: sets.map { set in
                CompletedWatchSet(
                    id: set.id,
                    plannedReps: set.plannedReps,
                    actualReps: set.actualReps,
                    plannedWeight: set.plannedWeight,
                    actualWeight: set.actualWeight,
                    restTime: set.restTime,
                    isCompleted: set.isCompleted,
                    completedAt: set.completedAt,
                    order: set.order
                )
            },
            order: order,
            supersetId: supersetId,
            supersetOrder: supersetOrder
        )
    }
}
