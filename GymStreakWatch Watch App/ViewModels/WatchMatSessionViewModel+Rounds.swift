//
//  WatchMatSessionViewModel+Rounds.swift
//  GymStreakWatch Watch App
//
//  The round timer on the watch (positioning ticket 07,
//  docs/fight-conditioning.md "Round timer"): the mat-session recorder plus a
//  timeline — no runner of its own. The recorder ticks the timeline, plays its
//  cues and ends into the usual review when the last round is over; this file
//  holds the entry point and the read-outs the views show.
//

import Foundation
import WatchKit

extension WatchMatSessionViewModel {

    /// A mat session whose clock also runs the rounds, saved as a session of the
    /// preset's sport — or discarded from the review. What was started is what
    /// the setup opens on next time.
    func startRoundTimer(_ configuration: RoundTimerConfiguration) async {
        roundTimerSettings?.save(configuration)
        let sport = WatchMatSport(rawValue: configuration.preset.matSportRawValue) ?? .other
        await begin(sport: sport, rounds: configuration)
    }

    /// What the setup screen opens on: the last configuration started, else the default.
    var lastRoundTimerConfiguration: RoundTimerConfiguration {
        roundTimerSettings?.load() ?? .default
    }

    var isRoundTimer: Bool { rounds != nil }

    /// Rounds fully finished; 0 without a plan.
    var completedRounds: Int {
        roundTimeline?.completedWorkIntervals(at: elapsed) ?? 0
    }

    /// The round timer's haptics: the conditioning runner's, except that the end
    /// of the timeline plays nothing extra — `end()` plays the stop.
    static func haptic(for cue: ConditioningRunCue) -> WKHapticType? {
        cue == .finished ? nil : WatchConditioningRunViewModel.haptic(for: cue)
    }
}
