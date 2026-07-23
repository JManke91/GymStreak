//
//  SwiftDataExerciseRepository.swift
//  GymStreak
//

import Foundation
import SwiftData

@MainActor
final class SwiftDataExerciseRepository: ExerciseRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() -> [Exercise] {
        let descriptor = FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name, order: .forward)])
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("Error fetching exercises: \(error)")
            return []
        }
    }

    func fetch(id: UUID) -> Exercise? {
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    func fetchBySeedKey(_ seedKey: String) -> [Exercise] {
        let trimmed = seedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.seedKey == trimmed })
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func insert(_ exercise: Exercise) {
        modelContext.insert(exercise)
    }

    func delete(_ exercise: Exercise) {
        modelContext.delete(exercise)
    }

    func save() throws {
        try modelContext.save()
    }
}
