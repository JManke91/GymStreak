import Foundation

/// Reads the durable HealthKit correlation identities already represented by
/// workout history. Reconciliation must not depend on a ViewModel's cached
/// SwiftData models because watch ingestion commits in a sibling context.
@MainActor
protocol WorkoutHistoryCorrelationProviding: AnyObject {
    func healthKitWorkoutIDs() throws -> Set<UUID>
}
