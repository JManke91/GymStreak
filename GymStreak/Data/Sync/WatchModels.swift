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
    let supersetId: UUID?
    let supersetOrder: Int
    var targetRepMin: Int? = nil
    var targetRepMax: Int? = nil
    var exerciseId: UUID? = nil
    var loadBehaviorRaw: String? = nil
    // Optional (nil default) keeps old cached payloads decodable.
    var alternatives: [WatchExerciseAlternative]? = nil
}

struct WatchSet: Codable, Identifiable, Hashable {
    let id: UUID
    let reps: Int
    let weight: Double
    let restTime: TimeInterval
}

/// An alternative exercise a user can swap to during a workout (with its own set scheme).
struct WatchExerciseAlternative: Codable, Identifiable, Hashable {
    let id: UUID          // RoutineExerciseAlternative.id
    let exerciseId: UUID  // the alternative Exercise's id
    let name: String
    let muscleGroup: String
    let sets: [WatchSet]
    let order: Int
    var loadBehaviorRaw: String? = nil
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

    // Template-transaction ordering identity (ticket 05). Optional (nil
    // default) keeps old payloads decodable. Assigned by the watch sync-state
    // owner in the same atomic commit as the enqueue, only when
    // `shouldUpdateTemplate == true`; stable across retries. The transaction
    // ID is the semantic transaction identity; the workout id is correlation.
    var templateTransactionID: UUID? = nil
    /// Persistent watch sender epoch shared by every template-mutating kind.
    var templateSenderEpoch: UUID? = nil
    /// Monotonic per-routine sequence within `templateSenderEpoch`.
    var templateSequence: UInt64? = nil

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
    var targetRepMin: Int? = nil
    var targetRepMax: Int? = nil
    var exerciseId: UUID? = nil
    var loadBehaviorRaw: String? = nil
    // Set only when the exercise was swapped for an alternative during the workout.
    // name/muscleGroup/exerciseId describe what was actually performed.
    var plannedExerciseId: UUID? = nil
    var plannedExerciseName: String? = nil
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

// MARK: - Wire DTO to Domain ingestion input

// Maps the decoded WatchConnectivity wire DTOs into the Domain-owned
// `IncomingWatchWorkout` model, keeping `CompletedWatchWorkout` (and its nested
// types) out of the Domain layer. Called at the WatchConnectivity boundary in
// `WatchConnectivityManager` before the payload reaches Domain/Presentation.

extension CompletedWatchWorkout {
    func toIncomingWatchWorkout() -> IncomingWatchWorkout {
        IncomingWatchWorkout(
            id: id,
            routineId: routineId,
            routineName: routineName,
            startTime: startTime,
            endTime: endTime,
            exercises: exercises.map { $0.toIncomingWatchExercise() },
            shouldUpdateTemplate: shouldUpdateTemplate,
            healthKitWorkoutId: healthKitWorkoutId,
            templateTransactionID: templateTransactionID,
            templateSenderEpoch: templateSenderEpoch,
            templateSequence: templateSequence
        )
    }
}

extension CompletedWatchExercise {
    func toIncomingWatchExercise() -> IncomingWatchExercise {
        IncomingWatchExercise(
            id: id,
            name: name,
            muscleGroup: muscleGroup,
            sets: sets.map { $0.toIncomingWatchSet() },
            order: order,
            supersetId: supersetId,
            supersetOrder: supersetOrder,
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            exerciseId: exerciseId,
            loadBehaviorRaw: loadBehaviorRaw ?? ExerciseLoadBehavior.resistance.rawValue,
            plannedExerciseId: plannedExerciseId,
            plannedExerciseName: plannedExerciseName
        )
    }
}

extension CompletedWatchSet {
    func toIncomingWatchSet() -> IncomingWatchSet {
        IncomingWatchSet(
            id: id,
            plannedReps: plannedReps,
            actualReps: actualReps,
            plannedWeight: plannedWeight,
            actualWeight: actualWeight,
            restTime: restTime,
            isCompleted: isCompleted,
            completedAt: completedAt,
            order: order
        )
    }
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
                    sets: routineExercise.setsList.sorted(by: { $0.order < $1.order }).map { set in
                        WatchSet(
                            id: set.id,
                            reps: set.reps,
                            weight: set.weight,
                            restTime: set.restTime
                        )
                    },
                    order: routineExercise.order,
                    supersetId: routineExercise.supersetId,
                    supersetOrder: routineExercise.supersetOrder,
                    targetRepMin: routineExercise.targetRepMin,
                    targetRepMax: routineExercise.targetRepMax,
                    exerciseId: routineExercise.exercise?.id,
                    loadBehaviorRaw: routineExercise.exercise?.loadBehavior.rawValue ?? ExerciseLoadBehavior.resistance.rawValue,
                    alternatives: routineExercise.alternativesList.compactMap { alternative in
                        guard let exercise = alternative.exercise else { return nil }
                        return WatchExerciseAlternative(
                            id: alternative.id,
                            exerciseId: exercise.id,
                            name: exercise.name,
                            muscleGroup: exercise.primaryMuscleGroup,
                            sets: alternative.setsList.map { set in
                                WatchSet(
                                    id: set.id,
                                    reps: set.reps,
                                    weight: set.weight,
                                    restTime: set.restTime
                                )
                            },
                            order: alternative.order,
                            loadBehaviorRaw: exercise.loadBehavior.rawValue
                        )
                    }
                )
            }
        )
    }
}
