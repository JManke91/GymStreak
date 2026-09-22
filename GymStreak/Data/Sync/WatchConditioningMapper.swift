//
//  WatchConditioningMapper.swift
//  GymStreak
//
//  Domain conditioning offer → the watch wire DTO (docs/fight-conditioning.md,
//  ticket 06). The watch runs the phases as sent, so expansion happens here.
//

import Foundation

enum WatchConditioningMapper {

    /// Domain offer → wire DTO. Swim is left out: the watch cannot configure a pool
    /// session without a lap length, and a touchscreen runner is no use in the water.
    static func program(from offer: ConditioningWatchOffer) -> WatchConditioningProgram {
        WatchConditioningProgram(
            day: offer.day,
            validUntil: offer.validUntil,
            sessions: offer.sessions.map { session in
                let definition = session.plan.definition
                let modalities = ([session.plan.modality] + definition.modalities)
                    .filter { $0 != .swim }
                return WatchConditioningSession(
                    sessionType: definition.id.rawValue,
                    energySystem: definition.energySystem.rawValue,
                    modalities: modalities.reduce(into: [String]()) { result, modality in
                        if !result.contains(modality.rawValue) { result.append(modality.rawValue) }
                    },
                    volume: session.plan.options.volume,
                    isSuggestedToday: session.isSuggestedToday,
                    phases: ConditioningTimeline.phases(for: definition, options: session.plan.options),
                    heartRateZone: session.heartRateTarget.map {
                        WatchHeartRateZone(lowerBPM: $0.lowerBPM, upperBPM: $0.upperBPM)
                    }
                )
            }
        )
    }
}
