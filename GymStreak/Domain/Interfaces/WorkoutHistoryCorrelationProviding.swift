import Foundation

/// Reads the durable HealthKit correlation identities already represented by
/// workout history. Reconciliation must not depend on a ViewModel's cached
/// SwiftData models because watch ingestion commits in a sibling context.
@MainActor
protocol WorkoutHistoryCorrelationProviding: AnyObject {
    func healthKitWorkoutIDs() throws -> Set<UUID>

    /// The committed history session id currently carrying `healthKitWorkoutId`,
    /// or nil if none. Recovery uses it to tell a saved placeholder apart from
    /// the rich session that later replaces it (the ingestion path materializes
    /// the replacement under a different session id). Replacement is atomic, so
    /// at any committed point at most one session carries a given id.
    func sessionID(forHealthKitWorkoutId id: UUID) throws -> UUID?
}
