//
//  ConditioningWorkoutSaving.swift
//  GymStreak
//
//  The Apple Health write for a finished conditioning session: its own
//  `HKWorkout`, never part of the strength workout (multi-activity sessions are
//  restricted to swim-bike-run). See docs/fight-conditioning.md.
//

import Foundation

@MainActor
protocol ConditioningWorkoutSaving: AnyObject {
    var isHealthKitAvailable: Bool { get }

    /// Asks for Health write access if it was never asked; a no-op otherwise.
    func prepareConditioningAuthorization() async

    /// Writes the session after the fact with the activity type for
    /// `modality`, stamping `HKMetadataKeyExternalUUID`.
    /// - Returns: the external UUID.
    @discardableResult
    func saveConditioningWorkout(
        modality: ConditioningModality,
        startDate: Date,
        endDate: Date,
        title: String
    ) async throws -> UUID
}
