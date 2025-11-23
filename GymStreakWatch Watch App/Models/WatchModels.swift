import Foundation

// MARK: - Lightweight models for Watch app
// These are Codable structs used for syncing between iOS and watchOS

struct WatchRoutine: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let exercises: [WatchExercise]

    var totalSets: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    var exerciseCount: Int {
        exercises.count
    }
}

struct WatchExercise: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let muscleGroup: String
    let sets: [WatchSet]
    let order: Int
}

struct WatchSet: Codable, Identifiable, Hashable {
    let id: UUID
    let reps: Int
    let weight: Double
    let restTime: TimeInterval
}

// MARK: - Active Workout State Models

struct ActiveWorkoutExercise: Identifiable {
    let id: UUID
    let name: String
    let muscleGroup: String
    var sets: [ActiveWorkoutSet]
    let order: Int

    var completedSetsCount: Int {
        sets.filter(\.isCompleted).count
    }

    var isComplete: Bool {
        sets.allSatisfy(\.isCompleted)
    }
}

struct ActiveWorkoutSet: Identifiable {
    let id: UUID
    var plannedReps: Int
    var actualReps: Int
    var plannedWeight: Double
    var actualWeight: Double
    var restTime: TimeInterval
    var isCompleted: Bool
    var completedAt: Date?
    let order: Int

    var wasModified: Bool {
        actualReps != plannedReps || actualWeight != plannedWeight
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

extension WatchExercise {
    func toActiveWorkoutExercise() -> ActiveWorkoutExercise {
        ActiveWorkoutExercise(
            id: UUID(),
            name: name,
            muscleGroup: muscleGroup,
            sets: sets.enumerated().map { index, set in
                ActiveWorkoutSet(
                    id: UUID(),
                    plannedReps: set.reps,
                    actualReps: set.reps,
                    plannedWeight: set.weight,
                    actualWeight: set.weight,
                    restTime: set.restTime,
                    isCompleted: false,
                    completedAt: nil,
                    order: index
                )
            },
            order: order
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
            order: order
        )
    }
}
