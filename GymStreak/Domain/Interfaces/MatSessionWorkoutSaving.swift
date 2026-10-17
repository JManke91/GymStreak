//
//  MatSessionWorkoutSaving.swift
//  GymStreak
//
//  The Apple Health write for a logged mat session. See docs/fight-conditioning.md.
//

import Foundation

@MainActor
protocol MatSessionWorkoutSaving: AnyObject {
    var isHealthKitAvailable: Bool { get }

    /// Asks for Health write access if it was never asked; a no-op otherwise.
    func prepareConditioningAuthorization() async

    /// Writes the session after the fact with the activity type for `sport`,
    /// stamping `externalUUID` (the `MatSession` id) as `HKMetadataKeyExternalUUID`.
    func saveMatSessionWorkout(
        externalUUID: UUID,
        sport: MatSport,
        startDate: Date,
        endDate: Date,
        title: String
    ) async throws
}
