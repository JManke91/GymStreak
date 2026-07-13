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

    func estimateCaloriesBurned(durationInSeconds: TimeInterval) -> Double { 0 }
}
