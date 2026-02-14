import Foundation
import SwiftData

@Model
final class Routine {
    var id: UUID = UUID()
    var name: String = ""
    @Relationship(deleteRule: .cascade, inverse: \RoutineExercise.routine)
    var routineExercises: [RoutineExercise]? = []
    @Relationship(inverse: \WorkoutSession.routine)
    var workoutSessions: [WorkoutSession]? = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.routineExercises = []
        self.workoutSessions = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // Convenience accessor for non-optional usage
    var routineExercisesList: [RoutineExercise] {
        routineExercises ?? []
    }

    /// Groups exercises by superset for display purposes.
    /// Returns arrays where standalone exercises are single-element arrays
    /// and superset exercises are grouped together in order.
    var exercisesGroupedBySupersets: [[RoutineExercise]] {
        let sorted = routineExercisesList.sorted { $0.order < $1.order }
        var groups: [[RoutineExercise]] = []
        var processedSupersetIds: Set<UUID> = []

        for exercise in sorted {
            if let supersetId = exercise.supersetId {
                // Skip if we've already processed this superset
                guard !processedSupersetIds.contains(supersetId) else { continue }
                processedSupersetIds.insert(supersetId)

                // Gather all exercises in this superset, sorted by supersetOrder
                let supersetExercises = sorted
                    .filter { $0.supersetId == supersetId }
                    .sorted { $0.supersetOrder < $1.supersetOrder }
                groups.append(supersetExercises)
            } else {
                // Standalone exercise
                groups.append([exercise])
            }
        }

        return groups
    }
}

@Model
final class Exercise {
    var id: UUID = UUID()
    var name: String = ""
    var muscleGroups: [String] = ["General"]
    var equipmentTypeRaw: String = EquipmentType.dumbbell.rawValue
    @Relationship(inverse: \RoutineExercise.exercise)
    var routineExercises: [RoutineExercise]? = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// The equipment type for this exercise
    var equipmentType: EquipmentType {
        get { EquipmentType(rawValue: equipmentTypeRaw) ?? .dumbbell }
        set { equipmentTypeRaw = newValue.rawValue }
    }

    init(name: String, muscleGroups: [String] = ["Chest"], equipmentType: EquipmentType = .dumbbell) {
        self.id = UUID()
        self.name = name
        self.muscleGroups = muscleGroups
        self.equipmentTypeRaw = equipmentType.rawValue
        self.routineExercises = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Convenience computed property for backwards compatibility and display
    var primaryMuscleGroup: String {
        muscleGroups.first ?? "Chest"
    }

    /// Formatted string for displaying all muscle groups
    var muscleGroupsDisplay: String {
        muscleGroups.joined(separator: ", ")
    }
}

@Model
final class RoutineExercise {
    var id: UUID = UUID()
    var routine: Routine?
    var exercise: Exercise?
    @Relationship(deleteRule: .cascade, inverse: \ExerciseSet.routineExercise)
    var sets: [ExerciseSet]? = []
    var order: Int = 0

    // Superset fields - iCloud compatible with default values
    var supersetId: UUID? = nil  // Nil if not in superset; shared UUID groups exercises
    var supersetOrder: Int = 0    // Order within superset (0 = first, 1 = second, etc.)

    init(exercise: Exercise, order: Int) {
        self.id = UUID()
        self.exercise = exercise
        self.sets = []
        self.order = order
    }

    // Convenience accessor for non-optional usage
    var setsList: [ExerciseSet] {
        sets ?? []
    }

    var isInSuperset: Bool {
        supersetId != nil
    }
}

@Model
final class ExerciseSet {
    var id: UUID = UUID()
    var reps: Int = 0
    var weight: Double = 0.0
    var restTime: TimeInterval = 60
    var isCompleted: Bool = false
    var order: Int = 0
    var routineExercise: RoutineExercise?

    init(reps: Int, weight: Double, restTime: TimeInterval, order: Int = 0) {
        self.id = UUID()
        self.reps = reps
        self.weight = weight
        self.restTime = restTime
        self.isCompleted = false
        self.order = order
    }
}

// Data structure to hold exercise information before creating the actual exercise
struct ExerciseData {
    let name: String
    let numberOfSets: Int
    let repsPerSet: Int
    let weightPerSet: Double
    let restTime: TimeInterval
}

// MARK: - Workout Recording Models

@Model
final class WorkoutSession {
    var id: UUID = UUID()
    var routine: Routine?
    var routineName: String = "" // Denormalized for history display
    var startTime: Date = Date()
    var endTime: Date?
    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workoutSession)
    var workoutExercises: [WorkoutExercise]? = []
    var notes: String = ""
    var didUpdateTemplate: Bool = false
    /// The UUID used as HKMetadataKeyExternalUUID when the workout was saved to HealthKit.
    /// Used to correlate this SwiftData record with its HealthKit counterpart.
    var healthKitWorkoutId: UUID?

    init(routine: Routine) {
        self.id = UUID()
        self.routine = routine
        self.routineName = routine.name
        self.startTime = Date()
        self.endTime = nil
        self.workoutExercises = []
        self.notes = ""
        self.didUpdateTemplate = false
    }

    // Convenience accessor for non-optional usage
    var workoutExercisesList: [WorkoutExercise] {
        workoutExercises ?? []
    }

    var duration: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }

    var completedSetsCount: Int {
        workoutExercisesList.flatMap(\.setsList).filter(\.isCompleted).count
    }

    var totalSetsCount: Int {
        workoutExercisesList.flatMap(\.setsList).count
    }

    var completionPercentage: Int {
        guard totalSetsCount > 0 else { return 0 }
        return Int((Double(completedSetsCount) / Double(totalSetsCount)) * 100)
    }

    var totalVolume: Double {
        workoutExercisesList.flatMap(\.setsList)
            .filter(\.isCompleted)
            .reduce(0) { $0 + ($1.actualWeight * Double($1.actualReps)) }
    }

    /// Groups workout exercises by superset for display purposes.
    var exercisesGroupedBySupersets: [[WorkoutExercise]] {
        let sorted = workoutExercisesList.sorted { $0.order < $1.order }
        var groups: [[WorkoutExercise]] = []
        var processedSupersetIds: Set<UUID> = []

        for exercise in sorted {
            if let supersetId = exercise.supersetId {
                guard !processedSupersetIds.contains(supersetId) else { continue }
                processedSupersetIds.insert(supersetId)

                let supersetExercises = sorted
                    .filter { $0.supersetId == supersetId }
                    .sorted { $0.supersetOrder < $1.supersetOrder }
                groups.append(supersetExercises)
            } else {
                groups.append([exercise])
            }
        }

        return groups
    }
}

@Model
final class WorkoutExercise {
    var id: UUID = UUID()
    var workoutSession: WorkoutSession?
    var exerciseName: String = "" // Denormalized for history display
    var muscleGroups: [String] = []
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.workoutExercise)
    var sets: [WorkoutSet]? = []
    var order: Int = 0

    // Superset fields - denormalized from RoutineExercise for history
    var supersetId: UUID? = nil  // iCloud compatible - must have default
    var supersetOrder: Int = 0    // iCloud compatible - must have default

    init(from routineExercise: RoutineExercise, order: Int) {
        self.id = UUID()
        self.exerciseName = routineExercise.exercise?.name ?? "Unknown"
        self.muscleGroups = routineExercise.exercise?.muscleGroups ?? ["General"]
        self.order = order
        // Copy superset fields from routine
        self.supersetId = routineExercise.supersetId
        self.supersetOrder = routineExercise.supersetOrder
        // Copy sets from routine, sorted by order
        self.sets = routineExercise.setsList.sorted(by: { $0.order < $1.order }).enumerated().map { index, set in
            WorkoutSet(from: set, order: index)
        }
    }

    init(exerciseName: String, muscleGroups: [String], order: Int) {
        self.id = UUID()
        self.exerciseName = exerciseName
        self.muscleGroups = muscleGroups
        self.order = order
        self.sets = []
    }

    // Convenience accessor for non-optional usage
    var setsList: [WorkoutSet] {
        sets ?? []
    }

    /// Convenience computed property for backwards compatibility
    var primaryMuscleGroup: String {
        muscleGroups.first ?? "General"
    }

    var completedSetsCount: Int {
        setsList.filter(\.isCompleted).count
    }

    var isInSuperset: Bool {
        supersetId != nil
    }
}

@Model
final class WorkoutSet {
    var id: UUID = UUID()
    var plannedReps: Int = 0
    var actualReps: Int = 0
    var plannedWeight: Double = 0.0
    var actualWeight: Double = 0.0
    var restTime: TimeInterval = 60
    var isCompleted: Bool = false
    var completedAt: Date?
    var order: Int = 0
    var workoutExercise: WorkoutExercise?

    init(from exerciseSet: ExerciseSet, order: Int) {
        self.id = UUID()
        self.plannedReps = exerciseSet.reps
        self.actualReps = exerciseSet.reps
        self.plannedWeight = exerciseSet.weight
        self.actualWeight = exerciseSet.weight
        self.restTime = exerciseSet.restTime
        self.isCompleted = false
        self.completedAt = nil
        self.order = order
    }

    init(plannedReps: Int, actualReps: Int, plannedWeight: Double, actualWeight: Double, restTime: TimeInterval, order: Int) {
        self.id = UUID()
        self.plannedReps = plannedReps
        self.actualReps = actualReps
        self.plannedWeight = plannedWeight
        self.actualWeight = actualWeight
        self.restTime = restTime
        self.isCompleted = false
        self.completedAt = nil
        self.order = order
    }
}
