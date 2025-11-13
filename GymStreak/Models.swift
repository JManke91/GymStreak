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
    var muscleGroup: String
    var exerciseDescription: String
    var createdAt: Date
    var updatedAt: Date
    
    init(name: String, muscleGroup: String = "General", exerciseDescription: String = "") {
        self.id = UUID()
        self.name = name
        self.muscleGroup = muscleGroup
        self.exerciseDescription = exerciseDescription
        self.createdAt = Date()
        self.updatedAt = Date()
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
    var routineExercise: RoutineExercise?
    
    init(reps: Int, weight: Double, restTime: TimeInterval) {
        self.id = UUID()
        self.reps = reps
        self.weight = weight
        self.restTime = restTime
        self.isCompleted = false
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
