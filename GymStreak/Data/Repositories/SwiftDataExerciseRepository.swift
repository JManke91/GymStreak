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
