//
//  WatchMatSessionViewModel+State.swift
//  GymStreakWatch Watch App
//
//  The mat-session recorder's states and review values (positioning ticket 05,
//  docs/fight-conditioning.md), apart so the view model stays under 300 lines.
//

import Foundation

extension WatchMatSessionViewModel {

    enum HealthOutcome: Equatable { case saved, failed, notSaved }

    struct Review: Equatable {
        let duration: TimeInterval
        let averageHeartRate: Int?
        let maximumHeartRate: Int?
        /// `nil` without heart-rate zones or with too little heart rate — the user picks.
        let suggested: WatchMatIntensity?
    }

    enum State: Equatable {
        case idle
        case couldNotStart
        case running
        case paused
        /// Ended; the user confirms the intensity before it is saved.
        case reviewing(Review)
        case saving
        case finished(HealthOutcome)
    }
}
