//
//  MatSessionCopy.swift
//  GymStreak
//
//  Localized display text and symbols for the mat-session vocabulary.
//

import Foundation

enum MatSessionCopy {

    static func sport(_ sport: MatSport) -> String {
        "mat.sport.\(sport.rawValue)".localized
    }

    static func intensity(_ intensity: MatIntensity) -> String {
        "mat.intensity.\(intensity.rawValue)".localized
    }

    static func sportSymbol(_ sport: MatSport) -> String {
        switch sport {
        case .bjj, .mma: "figure.martial.arts"
        case .muayThai: "figure.kickboxing"
        case .boxing: "figure.boxing"
        case .wrestling: "figure.wrestling"
        case .other: "figure.mixed.cardio"
        }
    }
}
