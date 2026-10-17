//
//  SwiftDataMatSessionRepository.swift
//  GymStreak
//

import Foundation
import SwiftData

@MainActor
final class SwiftDataMatSessionRepository: MatSessionRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func find(id: UUID) -> MatSession? {
        var descriptor = FetchDescriptor<MatSession>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            print("Error fetching mat session \(id): \(error)")
            return nil
        }
    }

    func insert(_ session: MatSession) {
        modelContext.insert(session)
    }

    func delete(_ session: MatSession) {
        modelContext.delete(session)
    }

    func save() throws {
        try modelContext.save()
    }
}
