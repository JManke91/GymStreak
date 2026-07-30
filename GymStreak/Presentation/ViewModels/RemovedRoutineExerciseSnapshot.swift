import Foundation

/// Value copy of a routine exercise taken just before it is deleted, so the
/// sorting mode's undo toast can put it back. SwiftData deletion cascades to
/// sets and alternatives, so everything has to be captured up front.
struct RemovedRoutineExerciseSnapshot {
    struct SetValues {
        let reps: Int
        let weight: Double
        let restTime: TimeInterval
        let order: Int
    }

    struct AlternativeValues {
        let exercise: Exercise?
        let order: Int
        let targetRepMin: Int?
        let targetRepMax: Int?
        let sets: [SetValues]
    }

    let exercise: Exercise?
    let order: Int
    let targetRepMin: Int?
    let targetRepMax: Int?
    let supersetId: UUID?
    let supersetOrder: Int
    let sets: [SetValues]
    let alternatives: [AlternativeValues]

    init(_ routineExercise: RoutineExercise) {
        exercise = routineExercise.exercise
        order = routineExercise.order
        targetRepMin = routineExercise.targetRepMin
        targetRepMax = routineExercise.targetRepMax
        supersetId = routineExercise.supersetId
        supersetOrder = routineExercise.supersetOrder
        sets = routineExercise.setsList
            .sorted { $0.order < $1.order }
            .map { SetValues(reps: $0.reps, weight: $0.weight, restTime: $0.restTime, order: $0.order) }
        alternatives = routineExercise.alternativesList.map { alternative in
            AlternativeValues(
                exercise: alternative.exercise,
                order: alternative.order,
                targetRepMin: alternative.targetRepMin,
                targetRepMax: alternative.targetRepMax,
                sets: alternative.setsList.map {
                    SetValues(reps: $0.reps, weight: $0.weight, restTime: $0.restTime, order: $0.order)
                }
            )
        }
    }
}
