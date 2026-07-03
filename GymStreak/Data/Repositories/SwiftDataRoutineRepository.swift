//
//  SwiftDataRoutineRepository.swift
//  GymStreak
//

import Foundation
import SwiftData

@MainActor
final class SwiftDataRoutineRepository: RoutineRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() -> [Routine] {
        let descriptor = FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("Error fetching routines: \(error)")
            return []
        }
    }

    func fetch(id: UUID) -> Routine? {
        let descriptor = FetchDescriptor<Routine>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    func fetch(name: String) -> Routine? {
        let descriptor = FetchDescriptor<Routine>(predicate: #Predicate { $0.name == name })
        return try? modelContext.fetch(descriptor).first
    }

    func insert(_ routine: Routine) {
        modelContext.insert(routine)
    }

    func delete(_ routine: Routine) {
        modelContext.delete(routine)
    }

    func delete(_ routineExercise: RoutineExercise) {
        modelContext.delete(routineExercise)
    }

    func insert(_ set: ExerciseSet) {
        modelContext.insert(set)
    }

    func delete(_ set: ExerciseSet) {
        modelContext.delete(set)
    }

    func delete(_ alternative: RoutineExerciseAlternative) {
        modelContext.delete(alternative)
    }

    func delete(_ set: AlternativeExerciseSet) {
        modelContext.delete(set)
    }

    func save() throws {
        try modelContext.save()
    }
}
