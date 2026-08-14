//
//  RestTimerAttributes.swift
//  GymStreak
//
//  Created by Claude on 15.11.25.
//
//  ⚠️ DUPLICATED PER TARGET — the declarations below must stay identical to
//  `GymStreakWidgets/RestTimerAttributes.swift`. ActivityKit pairs the app's
//  `Activity<RestTimerAttributes>` with the extension's
//  `ActivityConfiguration<RestTimerAttributes>` by attributes type, and decodes
//  `ContentState` across the process boundary — so a field that exists on only
//  one side silently breaks the Live Activity at runtime with no compile error
//  (the same failure shape as the watch wire drift in audit P1.4).
//
//  Lives in `Data/` rather than `Domain/`: it imports ActivityKit, and it is
//  the wire format of one system integration, not a domain model. Its only
//  app-target user is `ActivityKitRestTimerPresenter` in this folder.
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
