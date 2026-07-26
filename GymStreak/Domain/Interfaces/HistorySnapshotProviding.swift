//
//  HistorySnapshotProviding.swift
//  GymStreak
//

import Foundation

/// Read boundary for the History feature.
///
/// Implementations own their persistence context and never expose `PersistentModel` instances
/// across the async boundary. This keeps unbounded fetches, relationship faulting and aggregation
/// off the main actor while Presentation receives immutable values.
protocol HistorySnapshotProviding: Sendable {
    func fetchTrainingSnapshot(referenceDate: Date) async throws -> HistorySnapshot
    func fetchFortschrittSnapshot() async throws -> [FortschrittExerciseModel]
    func fetchPRDetails(sessionID: UUID) async throws -> [UUID: PersonalRecordService.PRDetail]
}

extension Notification.Name {
    /// Posted after a successful local mutation to routine or exercise data that contributes to
    /// History snapshots. The app-lifetime History `WorkoutViewModel` translates this event into
    /// its lightweight version token; no SwiftData models or repositories cross ViewModel seams.
    static let historySourceDataDidChange = Notification.Name("historySourceDataDidChange")
}
