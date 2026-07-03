//
//  SwiftDataWorkoutSessionRepository.swift
//  GymStreak
//

import Foundation
import SwiftData

@MainActor
final class SwiftDataWorkoutSessionRepository: WorkoutSessionRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() -> [WorkoutSession] {
        let descriptor = FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startTime, order: .reverse)])
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("Error fetching workout history: \(error)")
            return []
        }
    }

    func fetchCompleted() -> [WorkoutSession] {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endTime != nil },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("Error fetching completed workout sessions: \(error)")
            return []
        }
    }

    func findSession(id: UUID, healthKitWorkoutId: UUID?) -> WorkoutSession? {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.id == id || (healthKitWorkoutId != nil && session.healthKitWorkoutId == healthKitWorkoutId)
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    func insert(_ session: WorkoutSession) {
        modelContext.insert(session)
    }

    func delete(_ session: WorkoutSession) {
        modelContext.delete(session)
    }

    func insert(_ exercise: WorkoutExercise) {
        modelContext.insert(exercise)
    }

    func delete(_ exercise: WorkoutExercise) {
        modelContext.delete(exercise)
    }

    func insert(_ set: WorkoutSet) {
        modelContext.insert(set)
    }

    func delete(_ set: WorkoutSet) {
        modelContext.delete(set)
    }

    func save() throws {
        try modelContext.save()
    }
}
