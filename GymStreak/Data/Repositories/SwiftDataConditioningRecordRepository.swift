//
//  SwiftDataConditioningRecordRepository.swift
//  GymStreak
//

import Foundation
import SwiftData

@MainActor
final class SwiftDataConditioningRecordRepository: ConditioningRecordRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// No `relationshipKeyPathsForPrefetching`: the record has no relationships.
    /// Every value History renders is a stored attribute of the row itself,
    /// which is the whole point of denormalizing it.
    func fetchAll() -> [ConditioningRecord] {
        let descriptor = FetchDescriptor<ConditioningRecord>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("Error fetching conditioning history: \(error)")
            return []
        }
    }

    func find(id: UUID) -> ConditioningRecord? {
        var descriptor = FetchDescriptor<ConditioningRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            print("Error fetching conditioning record \(id): \(error)")
            return nil
        }
    }

    func insert(_ record: ConditioningRecord) {
        modelContext.insert(record)
    }

    func delete(_ record: ConditioningRecord) {
        modelContext.delete(record)
    }

    func save() throws {
        try modelContext.save()
    }
}
