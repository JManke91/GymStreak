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
    /// Deleting requires *share* authorization for the workout type, which does
    /// not survive the app being deleted and reinstalled even though the id
    /// does (it comes back over CloudKit). Implementations therefore re-ask for
    /// it in place and throw `HealthKitError.healthAccessDenied` when it is not
    /// granted — a state with a user remedy, distinct from `deleteFailed`.
    ///
    /// - Returns: `true` when a matching workout was deleted, `false` when
    ///   nothing matched — the user already removed it in the Health app, or it
    ///   was never there. The desired end state holds either way, so that is a
    ///   success and never an error.
    @discardableResult
    func deleteWorkout(externalUUID: UUID) async throws -> Bool

    func estimateCaloriesBurned(durationInSeconds: TimeInterval) -> Double
}

// MARK: - Error Types

/// The failure vocabulary of the HealthKit gateway.
///
/// Declared alongside the protocol rather than with its implementation so
/// callers in `Presentation/` can classify a failure without reaching into
/// `Data/`.
enum HealthKitError: LocalizedError {
    case notAvailable
    case notAuthorized
    case saveFailed(String)
    case deleteFailed(String)
    /// Apple Health will not let the app change workouts — the user declined the
    /// prompt, or revoked write access in Health. Distinct from `deleteFailed`
    /// because the remedy is a permission the user controls, not a retry.
    case healthAccessDenied

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .notAuthorized:
            return "HealthKit authorization not granted"
        case .saveFailed(let message):
            return "Failed to save workout: \(message)"
        case .deleteFailed(let message):
            return "Failed to delete workout: \(message)"
        case .healthAccessDenied:
            return "GymStreak is not allowed to change workouts in Apple Health"
        }
    }
}
