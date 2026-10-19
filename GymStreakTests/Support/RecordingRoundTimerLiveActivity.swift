//
//  RecordingRoundTimerLiveActivity.swift
//  GymStreakTests
//
//  Test double for the round timer's Lock Screen / Dynamic Island surface.
//  Records calls instead of talking to ActivityKit, which needs a real app
//  bundle with `NSSupportsLiveActivities` and the running system daemon.
//

import Foundation
@testable import GymStreak

@MainActor
final class RecordingRoundTimerLiveActivity: RoundTimerLiveActivityPresenting {
    private(set) var presented: [(id: UUID, content: RoundTimerLiveActivityContent)] = []
    private(set) var ended: [(id: UUID, completionMessage: String)] = []
    private(set) var dismissLeftoverCallCount = 0

    var lastContent: RoundTimerLiveActivityContent? { presented.last?.content }

    func presentActivity(id: UUID, content: RoundTimerLiveActivityContent) {
        presented.append((id, content))
    }

    func endActivity(id: UUID, completionMessage: String) {
        ended.append((id, completionMessage))
    }

    func dismissLeftoverActivities() {
        dismissLeftoverCallCount += 1
    }
}
