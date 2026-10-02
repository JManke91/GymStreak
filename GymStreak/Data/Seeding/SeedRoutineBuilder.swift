//
//  SeedRoutineBuilder.swift
//  GymStreak
//
//  The exercise resolution and routine construction shared by the example
//  routine seeder and the program installer. See docs/example-starter-routine.md
//  and docs/routine-programs.md.
//

import Foundation
import SwiftData

@MainActor
enum SeedRoutineBuilder {

    /// One resolved slot: the template plus the library exercises it points at.
    struct Slot {
        let template: SeedRoutineExercise
        let exercise: Exercise
        /// Each gets its own copy of the primary's set scheme and rep range.
        let alternatives: [Exercise]
    }

    /// The user's own loads are unknowable, and a fake starting number would
    /// poison their first progress chart.
    static let seededWeight = 0.0

    /// Seeded library exercises by `seedKey`, limited to `wanted`.
    static func seededExercisesBySeedKey(_ wanted: Set<String>, in context: ModelContext) throws -> [String: Exercise] {
        let exercises = try context.fetch(
            FetchDescriptor<Exercise>(predicate: #Predicate { $0.seedKey != "" })
        )
        // First wins on a duplicated key; `DefaultContentSeeder` has already
        // collapsed those by the time anything here runs.
        return Dictionary(
            exercises.filter { wanted.contains($0.seedKey) }.map { ($0.seedKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Inserts a seeded routine built from `slots`, in order.
    ///
    /// The localized name is resolved once here (device language) into the
    /// mutable `name`; `seedKey` stays the stable identity. `updatedAt` is pinned
    /// to `createdAt` — `Routine.init` stamps the two with separate `Date()` calls
    /// — which is what lets the example cleanup recognise an untouched routine.
    @discardableResult
    static func insertRoutine(seedKey: String, slots: [Slot], into context: ModelContext) -> Routine {
        // A superset needs two partners; one survivor is just an exercise.
        var membersPerGroup: [String: Int] = [:]
        for slot in slots {
            guard let group = slot.template.supersetGroup else { continue }
            membersPerGroup[group, default: 0] += 1
        }

        let routine = Routine(name: seedKey.localized)
        routine.seedKey = seedKey
        routine.updatedAt = routine.createdAt
        context.insert(routine)

        var supersetIds: [String: UUID] = [:]
        var supersetOrders: [String: Int] = [:]

        for (order, slot) in slots.enumerated() {
            let template = slot.template
            let routineExercise = RoutineExercise(exercise: slot.exercise, order: order)
            routineExercise.routine = routine
            routineExercise.targetRepMin = template.targetRepMin
            routineExercise.targetRepMax = template.targetRepMax

            if let group = template.supersetGroup, membersPerGroup[group, default: 0] >= 2 {
                let supersetId = supersetIds[group] ?? UUID()
                supersetIds[group] = supersetId
                routineExercise.supersetId = supersetId
                routineExercise.supersetOrder = supersetOrders[group, default: 0]
                supersetOrders[group, default: 0] += 1
            }

            for setOrder in 0..<template.setCount {
                let set = ExerciseSet(
                    reps: template.reps,
                    weight: seededWeight,
                    restTime: template.restTime,
                    order: setOrder
                )
                set.routineExercise = routineExercise
                routineExercise.sets?.append(set)
            }

            for (altOrder, exercise) in slot.alternatives.enumerated() {
                let alternative = RoutineExerciseAlternative(exercise: exercise, order: altOrder)
                alternative.routineExercise = routineExercise
                alternative.targetRepMin = template.targetRepMin
                alternative.targetRepMax = template.targetRepMax
                alternative.sets = (0..<template.setCount).map { setOrder in
                    let set = AlternativeExerciseSet(
                        reps: template.reps,
                        weight: seededWeight,
                        restTime: template.restTime,
                        order: setOrder
                    )
                    set.alternative = alternative
                    return set
                }
                if routineExercise.alternatives == nil { routineExercise.alternatives = [] }
                routineExercise.alternatives?.append(alternative)
            }

            routine.routineExercises?.append(routineExercise)
        }
        return routine
    }
}
