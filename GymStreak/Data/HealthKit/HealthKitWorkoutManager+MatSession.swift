//
//  HealthKitWorkoutManager+MatSession.swift
//  GymStreak
//
//  A logged mat session's Apple Health write: its own `HKWorkout` with the
//  sport's activity type, through the same after-the-fact builder as the
//  strength and conditioning saves. See docs/fight-conditioning.md.
//

import Foundation
import HealthKit

extension HealthKitWorkoutManager: MatSessionWorkoutSaving {

    /// Marks the workout for the recovery drain, which skips every workout carrying a
    /// session kind (`HealthKitAnchoredWorkoutDrain.facts(from:)`).
    static let matSessionKind = "mat"

    func saveMatSessionWorkout(
        externalUUID: UUID,
        sport: MatSport,
        startDate: Date,
        endDate: Date,
        title: String
    ) async throws {
        checkAuthorizationStatus()
        _ = try await writeWorkout(
            configuration: Self.configuration(for: sport),
            startDate: startDate,
            endDate: endDate,
            // No energy estimate: nothing measured it, and a flat per-minute rate
            // means nothing across drilling and hard sparring.
            totalEnergyBurned: nil,
            metadata: [
                HKMetadataKeyWorkoutBrandName: title,
                Self.sessionKindMetadataKey: Self.matSessionKind
            ],
            externalUUID: externalUUID
        )
    }

    /// BJJ, MMA and Muay Thai have no type of their own; `.martialArts` covers them.
    static func configuration(for sport: MatSport) -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = switch sport {
        case .bjj, .mma, .muayThai: .martialArts
        case .boxing: .boxing
        case .wrestling: .wrestling
        case .other: .other
        }
        configuration.locationType = .indoor
        return configuration
    }
}
