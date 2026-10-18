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
}
