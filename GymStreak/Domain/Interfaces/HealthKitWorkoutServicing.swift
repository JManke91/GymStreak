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

    func requestAuthorization() async throws
    func checkAuthorizationStatus()

    /// Writes a completed workout after the fact, stamping `metadata` (brand
    /// name + `HKMetadataKeyExternalUUID`) before collection ends.
    ///
    /// This is the *only* write path on iOS. Recording through a live
    /// `HKWorkoutSession` on iPhone was removed: it needs the
    /// `workout-processing` background mode this target does not declare, and
    /// its finalization order dropped the metadata, leaving workouts in Health
    /// with the generic activity name and no external UUID to correlate or
    /// delete by (`docs/healthkit-ios-workout-save.md`).
    func saveWorkoutDirectly(
        startDate: Date,
        endDate: Date,
        totalEnergyBurned: Double?,
        metadata: [String: Any]?
    ) async throws -> (workout: HKWorkout?, healthKitWorkoutId: UUID)

    /// Removes the Apple Health workout stamped with `externalUUID` in its
    /// `HKMetadataKeyExternalUUID` metadata — the same id stored on
    /// `WorkoutSession.healthKitWorkoutId`.
    ///
    /// - Returns: `true` when a matching workout was found and deleted, `false`
    ///   when nothing matched. A zero-result lookup is indistinguishable from a
    ///   silently denied read or a workout the user already removed in the Health
    ///   app; in all three cases the desired end state already holds, so it is a
    ///   success and never an error.
    @discardableResult
    func deleteWorkout(externalUUID: UUID) async throws -> Bool

    func estimateCaloriesBurned(durationInSeconds: TimeInterval) -> Double
}
