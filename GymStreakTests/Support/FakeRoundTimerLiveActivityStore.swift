//
//  FakeRoundTimerLiveActivityStore.swift
//  GymStreakTests
//
//  The injectable ActivityKit seam of `ActivityKitRoundTimerPresenter`, faked:
//  records requests, updates and ends so the presenter's policy can be
//  asserted without an app bundle or the system daemon. Used by
//  `ActivityKitRoundTimerPresenterTests`.
//

import Foundation
@testable import GymStreak

@MainActor
final class FakeRoundTimerLiveActivityHandle: RoundTimerLiveActivityHandle {
    private(set) var updates: [(content: RoundTimerLiveActivityContent, staleDate: Date?)] = []
    private(set) var endCalls: [(completionMessage: String?, dismissAfter: Date?)] = []
    var isEnded: Bool { !endCalls.isEmpty }

    func update(content: RoundTimerLiveActivityContent, staleDate: Date?) {
        updates.append((content, staleDate))
    }

    func end(completionMessage: String?, dismissAfter: Date?) {
        endCalls.append((completionMessage, dismissAfter))
    }
}

@MainActor
final class FakeRoundTimerLiveActivityStore: RoundTimerLiveActivityStore {
    var areActivitiesEnabled = true
    var requestError: Error?

    private(set) var requests: [(content: RoundTimerLiveActivityContent, staleDate: Date?)] = []
    /// Everything the system would still list, including activities this
    /// process did not start. An ended activity stays listed until it is
    /// dismissed, so ending does not remove it here either.
    var listedActivities: [FakeRoundTimerLiveActivityHandle] = []

    func currentActivities() -> [any RoundTimerLiveActivityHandle] {
        listedActivities
    }

    func requestActivity(
        content: RoundTimerLiveActivityContent,
        staleDate: Date?
    ) throws -> any RoundTimerLiveActivityHandle {
        requests.append((content, staleDate))
        if let requestError {
            throw requestError
        }
        let handle = FakeRoundTimerLiveActivityHandle()
        listedActivities.append(handle)
        return handle
    }
}
