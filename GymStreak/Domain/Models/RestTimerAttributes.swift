//
//  RestTimerAttributes.swift
//  GymStreak
//
//  Created by Claude on 15.11.25.
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
