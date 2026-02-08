import Foundation

// MARK: - Lightweight models for Watch app
// These are Codable structs used for syncing between iOS and watchOS
// This file is shared between iOS and Watch targets

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

// MARK: - SwiftData to Watch Model Conversion

extension Routine {
    func toWatchRoutine() -> WatchRoutine {
        let sortedExercises = routineExercisesList.sorted { $0.order < $1.order }
        return WatchRoutine(
            id: id,
            name: name,
            exercises: sortedExercises.map { routineExercise in
                WatchExercise(
                    id: routineExercise.id,
                    name: routineExercise.exercise?.name ?? "Unknown",
                    muscleGroup: routineExercise.exercise?.primaryMuscleGroup ?? "General",
                    sets: routineExercise.setsList.map { set in
                        WatchSet(
                            id: set.id,
                            reps: set.reps,
                            weight: set.weight,
                            restTime: set.restTime
                        )
                    },
                    order: routineExercise.order
                )
            }
        )
    }
}
