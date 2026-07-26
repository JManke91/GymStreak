import Foundation
import HealthKit
@testable import GymStreak

@MainActor
final class MockHealthKitWorkoutServicing: HealthKitWorkoutServicing {
    var isHealthKitAvailable = false
    var isAuthorized = false
    var isWorkoutActive = false

    func requestAuthorization() async throws {}
    func checkAuthorizationStatus() {}
    func startWorkoutSession() async throws {}
    func cancelWorkoutSession() {}

    func endWorkoutSession(
        totalEnergyBurned: Double?,
        metadata: [String: Any]?
    ) async throws -> (workout: HKWorkout?, healthKitWorkoutId: UUID) {
        (nil, UUID())
    }

    func saveWorkoutDirectly(
        startDate: Date,
        endDate: Date,
        totalEnergyBurned: Double?,
        metadata: [String: Any]?
    ) async throws -> (workout: HKWorkout?, healthKitWorkoutId: UUID) {
        (nil, UUID())
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
