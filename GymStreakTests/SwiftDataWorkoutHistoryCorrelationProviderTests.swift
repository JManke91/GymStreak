import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct SwiftDataWorkoutHistoryCorrelationProviderTests {
    @Test
    func readsHealthKitIdentityCommittedBySiblingContext() throws {
        let container = InMemoryModelContainer.make()
        let mainContext = container.mainContext
        _ = try mainContext.fetch(FetchDescriptor<WorkoutSession>())

        let healthKitID = UUID()
        let ingestionContext = ModelContext(container)
        ingestionContext.autosaveEnabled = false
        let session = WorkoutSession(routine: nil)
        session.healthKitWorkoutId = healthKitID
        ingestionContext.insert(session)
        try ingestionContext.save()

        let provider = SwiftDataWorkoutHistoryCorrelationProvider(container: container)
        #expect(try provider.healthKitWorkoutIDs() == [healthKitID])
    }
}
