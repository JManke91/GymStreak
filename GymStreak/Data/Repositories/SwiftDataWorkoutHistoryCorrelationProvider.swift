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
}
