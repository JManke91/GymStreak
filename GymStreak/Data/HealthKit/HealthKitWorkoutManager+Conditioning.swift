//
//  HealthKitWorkoutManager+Conditioning.swift
//  GymStreak
//
//  The conditioning session's Apple Health write: its own `HKWorkout` with the
//  modality's activity type, through the same after-the-fact builder as the
//  strength save. See docs/fight-conditioning.md.
//

import Foundation
import HealthKit

extension HealthKitWorkoutManager: ConditioningWorkoutSaving {

    /// Metadata marking a workout as a conditioning session. The recovery drain
    /// (`HealthKitAnchoredWorkoutDrain.facts(from:)`) skips marked workouts:
    /// they have no strength-history counterpart, so they would otherwise be
    /// offered as a "missing" workout and imported as a strength session.
    static let sessionKindMetadataKey = "GymStreakSessionKind"
    static let conditioningSessionKind = "conditioning"

    func prepareConditioningAuthorization() async {
        guard isHealthKitAvailable else { return }
        checkAuthorizationStatus()
        guard !isAuthorized else { return }
        do {
            // Already-decided types do not re-prompt; this only asks once.
            try await requestAuthorization()
        } catch {
            print("HealthKit authorization failed: \(error)")
        }
    }

    func saveConditioningWorkout(
        externalUUID: UUID,
        modality: ConditioningModality,
        startDate: Date,
        endDate: Date,
        title: String
    ) async throws {
        checkAuthorizationStatus()
        _ = try await writeWorkout(
            configuration: Self.configuration(for: modality),
            startDate: startDate,
            endDate: endDate,
            // No energy estimate: the phone has no sensor, and the strength
            // path's flat 4.5 kcal/min is meaningless for sprints.
            totalEnergyBurned: nil,
            metadata: [
                HKMetadataKeyWorkoutBrandName: title,
                Self.sessionKindMetadataKey: Self.conditioningSessionKind
            ],
            // The `ConditioningRecord` already carries this id.
            externalUUID: externalUUID
        )
    }

    /// Activity types per docs/fight-conditioning.md. Swim uses an unknown
    /// swimming location: `.pool` without a lap length renders oddly in Health,
    /// and the app does not know the pool length.
    static func configuration(for modality: ConditioningModality) -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        switch modality {
        case .run:
            configuration.activityType = .running
            configuration.locationType = .outdoor
        case .assaultBike:
            configuration.activityType = .cycling
            configuration.locationType = .indoor
        case .rower:
            configuration.activityType = .rowing
            configuration.locationType = .indoor
        case .swim:
            configuration.activityType = .swimming
            configuration.swimmingLocationType = .unknown
        case .sledRopesMedBall:
            configuration.activityType = .highIntensityIntervalTraining
            configuration.locationType = .indoor
        }
        return configuration
    }
}
