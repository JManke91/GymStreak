import Foundation
import SwiftData

@MainActor
final class SwiftDataWorkoutHistoryCorrelationProvider: WorkoutHistoryCorrelationProviding {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func healthKitWorkoutIDs() throws -> Set<UUID> {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        return Set(sessions.compactMap(\.healthKitWorkoutId))
    }

    func sessionID(forHealthKitWorkoutId id: UUID) throws -> UUID? {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.healthKitWorkoutId == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.id
    }
}
