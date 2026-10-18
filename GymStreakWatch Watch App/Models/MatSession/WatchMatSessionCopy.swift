//
//  WatchMatSessionCopy.swift
//  GymStreakWatch Watch App
//
//  Localized names and symbols for mat sessions on the watch — the iPhone's
//  `MatSessionCopy` wording, in the watch's English-key String Catalog.
//

import Foundation

enum WatchMatSessionCopy {

    static func sport(_ sport: WatchMatSport) -> String {
        switch sport {
        case .bjj: String(localized: "BJJ")
        case .mma: String(localized: "MMA")
        case .muayThai: String(localized: "Muay Thai")
        case .boxing: String(localized: "Boxing")
        case .wrestling: String(localized: "Wrestling")
        case .other: String(localized: "Other")
        }
    }

    static func intensity(_ intensity: WatchMatIntensity) -> String {
        switch intensity {
        case .drilling: String(localized: "Drilling")
        case .moderate: String(localized: "Moderate")
        case .hardSparring: String(localized: "Hard sparring")
        }
    }

    static func symbol(_ sport: WatchMatSport) -> String {
        switch sport {
        case .bjj, .mma: "figure.martial.arts"
        case .muayThai: "figure.kickboxing"
        case .boxing: "figure.boxing"
        case .wrestling: "figure.wrestling"
        case .other: "figure.mixed.cardio"
        }
    }

    // MARK: - Round timer (positioning ticket 07)

    /// A preset is named after its sport; custom is "Custom".
    static func preset(_ preset: RoundTimerPreset) -> String {
        guard preset != .custom, let matSport = WatchMatSport(rawValue: preset.matSportRawValue) else {
            return String(localized: "Custom")
        }
        return sport(matSport)
    }

    /// "5:00 / 1:00" — round and rest length.
    static func roundAndRest(round: TimeInterval, rest: TimeInterval) -> String {
        "\(WatchConditioningCopy.clock(round)) / \(WatchConditioningCopy.clock(rest))"
    }

    /// "Round 3/6", or "Round 3" when the timer is open-ended.
    static func round(_ phase: ConditioningPhase) -> String? {
        if let position = WatchConditioningCopy.position(phase) { return position }
        return phase.round.map { String(localized: "Round \($0)") }
    }
}
