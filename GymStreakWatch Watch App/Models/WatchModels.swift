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
    let supersetId: UUID?
    let supersetOrder: Int
    var targetRepMin: Int? = nil
    var targetRepMax: Int? = nil
    var exerciseId: UUID? = nil
    // Optional (nil default) keeps old cached payloads decodable.
    var alternatives: [WatchExerciseAlternative]? = nil

    /// Compact, consistent summary of planned sets.
    ///
    /// Always uses the format `<sets> × <reps> @ <weight>` with ascending ranges,
    /// e.g. "3 × 10 @ 80 kg", "3 × 8–12 @ 80 kg", "3 × 10 @ 60–80 kg".
    /// Bodyweight sets omit the weight part ("3 × 10"). Empty when no sets.
    var setsSummary: String {
        guard !sets.isEmpty else { return "" }

        let reps = sets.map(\.reps)
        let weights = sets.map(\.weight)
        let minReps = reps.min() ?? 0
        let maxReps = reps.max() ?? 0
        let minWeight = weights.min() ?? 0
        let maxWeight = weights.max() ?? 0
        let isBodyweight = maxWeight == 0

        func formatted(_ kg: Double) -> String {
            Measurement(value: kg, unit: UnitMass.kilograms)
                .formatted(.measurement(width: .abbreviated, usage: .general))
        }

        // Reps: single value when uniform, otherwise an ascending min–max range.
        let repsPart = minReps == maxReps ? "\(minReps)" : "\(minReps)–\(maxReps)"
        let setsAndReps = "\(sets.count) × \(repsPart)"

        // Bodyweight exercises omit the weight portion entirely.
        guard !isBodyweight else { return setsAndReps }

        // Weight: single value when uniform, otherwise an ascending min–max range.
        let weightPart = minWeight == maxWeight
            ? formatted(minWeight)
            : "\(formatted(minWeight))–\(formatted(maxWeight))"

        return "\(setsAndReps) @ \(weightPart)"
    }
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
}

// MARK: - Active Workout State Models

struct ActiveWorkoutExercise: Identifiable {
    let id: UUID
    // Mutable so swapping to an alternative updates the displayed identity in place.
    var name: String
    var muscleGroup: String
    var sets: [ActiveWorkoutSet]
    let order: Int
    let supersetId: UUID?
    let supersetOrder: Int
    var targetRepMin: Int? = nil
    var targetRepMax: Int? = nil
    var exerciseId: UUID? = nil
    // Alternative exercises available for swapping (with their own set schemes).
    var alternatives: [WatchExerciseAlternative] = []
    // Swap tracking: set on the first swap, cleared when reverting to the original.
    var plannedExerciseId: UUID? = nil
    var plannedExerciseName: String? = nil
    // Captured on first swap so the original exercise can be restored (revert).
    var originalMuscleGroup: String? = nil
    var originalSets: [WatchSet]? = nil

    var completedSetsCount: Int {
        sets.filter(\.isCompleted).count
    }

    var isComplete: Bool {
        sets.allSatisfy(\.isCompleted)
    }

    var isInSuperset: Bool {
        supersetId != nil
    }

    var wasSwapped: Bool {
        plannedExerciseId != nil
    }

    /// True if the exercise can still be swapped (no completed set, alternatives exist).
    var canSwap: Bool {
        completedSetsCount == 0 && !alternatives.isEmpty
    }

    var hasRepRangeGoal: Bool {
        targetRepMin != nil && targetRepMax != nil
    }

    var allCompletedSetsAtUpperLimit: Bool {
        guard let max = targetRepMax else { return false }
        guard !sets.isEmpty else { return false }
        return sets.allSatisfy { $0.isCompleted && $0.actualReps >= max }
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
        var repGoalAchieved: Bool = false
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
    var targetRepMin: Int? = nil
    var targetRepMax: Int? = nil
    var exerciseId: UUID? = nil
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

// MARK: - Conversion Extensions

extension WatchExercise {
    func toActiveWorkoutExercise() -> ActiveWorkoutExercise {
        // Preserve the original IDs from the lightweight Watch models so that
        // CompletedWatchWorkout sent back to the iPhone can be matched to the
        // iOS Routine/RoutineExercise/ExerciseSet by id.
        ActiveWorkoutExercise(
            id: id, // <-- preserve original WatchExercise id (was previously UUID())
            name: name,
            muscleGroup: muscleGroup,
            sets: sets.enumerated().map { index, set in
                ActiveWorkoutSet(
                    id: set.id, // <-- preserve original WatchSet id (was previously UUID())
                    plannedReps: set.reps,
                    actualReps: set.reps,
                    plannedWeight: set.weight,
                    actualWeight: set.weight,
                    restTime: set.restTime,
//                    isCompleted: false,
                    completedAt: nil,
                    order: index
                )
            },
            order: order,
            supersetId: supersetId,
            supersetOrder: supersetOrder,
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            exerciseId: exerciseId,
            alternatives: alternatives ?? []
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
            supersetOrder: supersetOrder,
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            exerciseId: exerciseId,
            plannedExerciseId: plannedExerciseId,
            plannedExerciseName: plannedExerciseName
        )
    }
}
