//
//  RecordingRestTimerLiveActivity.swift
//  GymStreakTests
//
//  Test double for the rest timer's Lock Screen / Dynamic Island surface.
//  Records calls instead of talking to ActivityKit, which needs a real app
//  bundle with `NSSupportsLiveActivities` and the running system daemon — so
//  this is what keeps ActivityKit out of the unit-test host entirely.
//

import Foundation
@testable import GymStreak

@MainActor
final class RecordingRestTimerLiveActivity: RestTimerLiveActivityPresenting {
    private(set) var startedActivities: [(id: UUID, content: RestTimerLiveActivityContent)] = []
    private(set) var endedActivityIDs: [UUID] = []
    private(set) var dismissExpiredCallCount = 0

    func startActivity(id: UUID, content: RestTimerLiveActivityContent) {
        startedActivities.append((id, content))
    }

    func endActivity(id: UUID) {
        endedActivityIDs.append(id)
    }

    func dismissExpiredActivities() {
        dismissExpiredCallCount += 1
    }
}
