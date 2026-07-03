//
//  HealthKitWorkoutServicing.swift
//  GymStreak
//
//  What the Presentation layer (WorkoutViewModel, SaveWorkoutView) needs from
//  HealthKitWorkoutManager. Lets ViewModels depend on a protocol instead of
//  the concrete HealthKit-backed class.
//

import Foundation
import HealthKit

@MainActor
protocol HealthKitWorkoutServicing: AnyObject {
    var isHealthKitAvailable: Bool { get }
    var isAuthorized: Bool { get }
    var isWorkoutActive: Bool { get }

    func requestAuthorization() async throws
    func checkAuthorizationStatus()

    func startWorkoutSession() async throws
    func cancelWorkoutSession()
    func endWorkoutSession(
        totalEnergyBurned: Double?,
        metadata: [String: Any]?
    ) async throws -> (workout: HKWorkout?, healthKitWorkoutId: UUID)

    /// Fallback: save a completed workout directly without an active session.
    func saveWorkoutDirectly(
        startDate: Date,
        endDate: Date,
        totalEnergyBurned: Double?,
        metadata: [String: Any]?
    ) async throws -> (workout: HKWorkout?, healthKitWorkoutId: UUID)

    func estimateCaloriesBurned(durationInSeconds: TimeInterval) -> Double
}
