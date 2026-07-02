import Foundation

/// A not-yet-persisted alternative exercise picked while configuring a routine
/// exercise. Carries its own editable set scheme; materialized into
/// RoutineExerciseAlternative at save.
@Observable
final class PendingAlternative: Identifiable, Hashable {
    let id = UUID()
    let exercise: Exercise
    var sets: [ExerciseSet]

    init(exercise: Exercise, sets: [ExerciseSet]) {
        self.exercise = exercise
        self.sets = sets
    }

    /// Seeds the set scheme from the given sets: set count, reps and rest carry
    /// over, but the weight starts empty — a different exercise almost always
    /// needs a different weight, so copying it would just be a wrong prefill.
    convenience init(exercise: Exercise, seededFrom sourceSets: [ExerciseSet], restTime: TimeInterval) {
        let copies = sourceSets.map { ExerciseSet(reps: $0.reps, weight: 0.0, restTime: restTime, order: $0.order) }
        self.init(
            exercise: exercise,
            sets: copies.isEmpty ? [ExerciseSet(reps: 10, weight: 0.0, restTime: restTime, order: 0)] : copies
        )
    }

    static func == (lhs: PendingAlternative, rhs: PendingAlternative) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
