//
//  RoundTimerAttributes.swift
//  GymStreak
//
//  ⚠️ DUPLICATED PER TARGET — the declarations below must stay identical to
//  `GymStreak/Data/LiveActivity/RoundTimerAttributes.swift`. ActivityKit pairs the app's
//  `Activity<RoundTimerAttributes>` with the extension's
//  `ActivityConfiguration<RoundTimerAttributes>` by attributes type, and decodes
//  `ContentState` across the process boundary — so a field that exists on only
//  one side silently breaks the Live Activity at runtime with no compile error
//  (the same failure shape as `RestTimerAttributes`).
//

import ActivityKit
import Foundation

struct RoundTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// The whole run, start to last bell, shifted by the pauses so far. The
        /// widget's timer views advance it without the app.
        var runRange: ClosedRange<Date>

        /// Set while paused: the timer views freeze at this instant.
        var pauseDate: Date?

        /// The current phase, trusted until `phaseRange` ends (the stale date).
        var phaseLabel: String?
        var phaseIsRound: Bool
        var phasePosition: String?
        var phaseRange: ClosedRange<Date>?

        /// The final state shown briefly when the run is over.
        var completionMessage: String?
    }

    // Fixed for the run.
    let title: String
    let subtitle: String
    let isOpenEnded: Bool
    let timeLabel: String
    let pausedLabel: String
    let staleNote: String
}
