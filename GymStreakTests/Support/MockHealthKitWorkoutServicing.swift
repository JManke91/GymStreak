import Foundation
import HealthKit
@testable import GymStreak

@MainActor
final class MockHealthKitWorkoutServicing: HealthKitWorkoutServicing {
    var isHealthKitAvailable = false
    var isAuthorized = false

    func requestAuthorization() async throws {}
    func checkAuthorizationStatus() {}

    // MARK: - Save

    /// One record per `saveWorkoutDirectly` call, in order.
    struct SavedWorkout {
        let startDate: Date
        let endDate: Date
        let totalEnergyBurned: Double?
        let metadata: [String: Any]?
        let healthKitWorkoutId: UUID
    }

    private(set) var savedWorkouts: [SavedWorkout] = []
    /// When set, `saveWorkoutDirectly(...)` throws it instead of saving.
    var saveError: Error?

    func saveWorkoutDirectly(
        startDate: Date,
        endDate: Date,
        totalEnergyBurned: Double?,
        metadata: [String: Any]?
    ) async throws -> (workout: HKWorkout?, healthKitWorkoutId: UUID) {
        if let saveError { throw saveError }
        let id = UUID()
        savedWorkouts.append(SavedWorkout(
            startDate: startDate,
            endDate: endDate,
            totalEnergyBurned: totalEnergyBurned,
            metadata: metadata,
            healthKitWorkoutId: id
        ))
        return (nil, id)
    }

    // MARK: - Delete

    /// External UUIDs the ViewModel asked to remove from HealthKit, in order.
    private(set) var deletedExternalUUIDs: [UUID] = []
    /// When set, `deleteWorkout(externalUUID:)` throws it instead of deleting.
    var deleteError: Error?
    /// What a successful delete reports: `false` models "already gone".
    var deleteResult = true

    @discardableResult
    func deleteWorkout(externalUUID: UUID) async throws -> Bool {
        deletedExternalUUIDs.append(externalUUID)
        if let deleteError { throw deleteError }
        return deleteResult
    }

    func estimateCaloriesBurned(durationInSeconds: TimeInterval) -> Double { 0 }
}
