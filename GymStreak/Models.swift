import Foundation
import SwiftData

@Model
final class Routine {
    var id: UUID
    var name: String
    var routineExercises: [RoutineExercise]
    var createdAt: Date
    var updatedAt: Date
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.routineExercises = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class Exercise {
    var id: UUID
    var name: String
    var muscleGroups: [String]
    var createdAt: Date
    var updatedAt: Date

    init(name: String, muscleGroups: [String] = ["Chest"]) {
        self.id = UUID()
        self.name = name
        self.muscleGroups = muscleGroups
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
    var id: UUID
    var routine: Routine?
    var exercise: Exercise?
    var sets: [ExerciseSet]
    var order: Int
    
    init(exercise: Exercise, order: Int) {
        self.id = UUID()
        self.exercise = exercise
        self.sets = []
        self.order = order
    }
}

@Model
final class ExerciseSet {
    var id: UUID
    var reps: Int
    var weight: Double
    var restTime: TimeInterval
    var isCompleted: Bool
    var order: Int
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
    var id: UUID
    var routine: Routine?
    var routineName: String // Denormalized for history display
    var startTime: Date
    var endTime: Date?
    var workoutExercises: [WorkoutExercise]
    var notes: String
    var didUpdateTemplate: Bool

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

    var duration: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }

    var completedSetsCount: Int {
        workoutExercises.flatMap(\.sets).filter(\.isCompleted).count
    }

    var totalSetsCount: Int {
        workoutExercises.flatMap(\.sets).count
    }

    var completionPercentage: Int {
        guard totalSetsCount > 0 else { return 0 }
        return Int((Double(completedSetsCount) / Double(totalSetsCount)) * 100)
    }

    var totalVolume: Double {
        workoutExercises.flatMap(\.sets)
            .filter(\.isCompleted)
            .reduce(0) { $0 + ($1.actualWeight * Double($1.actualReps)) }
    }
}

@Model
final class WorkoutExercise {
    var id: UUID
    var workoutSession: WorkoutSession?
    var exerciseName: String // Denormalized for history display
    var muscleGroups: [String]
    var sets: [WorkoutSet]
    var order: Int

    init(from routineExercise: RoutineExercise, order: Int) {
        self.id = UUID()
        self.exerciseName = routineExercise.exercise?.name ?? "Unknown"
        self.muscleGroups = routineExercise.exercise?.muscleGroups ?? ["General"]
        self.order = order
        // Copy sets from routine, sorted by order
        self.sets = routineExercise.sets.sorted(by: { $0.order < $1.order }).enumerated().map { index, set in
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

    /// Convenience computed property for backwards compatibility
    var primaryMuscleGroup: String {
        muscleGroups.first ?? "General"
    }

    var completedSetsCount: Int {
        sets.filter(\.isCompleted).count
    }
}

@Model
final class WorkoutSet {
    var id: UUID
    var plannedReps: Int
    var actualReps: Int
    var plannedWeight: Double
    var actualWeight: Double
    var restTime: TimeInterval
    var isCompleted: Bool
    var completedAt: Date?
    var order: Int
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
