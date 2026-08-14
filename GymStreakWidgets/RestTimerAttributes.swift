//
//  RestTimerAttributes.swift
//  GymStreak
//
//  Created by Claude on 15.11.25.
//
//  ⚠️ DUPLICATED PER TARGET — the declarations below must stay identical to
//  `GymStreak/Data/LiveActivity/RestTimerAttributes.swift`. ActivityKit pairs
//  the app's `Activity<RestTimerAttributes>` with this extension's
//  `ActivityConfiguration<RestTimerAttributes>` by attributes type, and decodes
//  `ContentState` across the process boundary — so a field that exists on only
//  one side silently breaks the Live Activity at runtime with no compile error
//  (the same failure shape as the watch wire drift in audit P1.4).
//

import ActivityKit
import Foundation

struct RestTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // The time range for the countdown timer
        var timerRange: ClosedRange<Date>

        // Optional context about current exercise
        var exerciseName: String?

        // Optional completion message
        var completionMessage: String?
    }

    // Fixed properties set when activity starts
    let workoutName: String
}
