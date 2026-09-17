//
//  FakeWorkoutReminderNotificationCenter.swift
//  GymStreakTests
//
//  A `WorkoutReminderNotificationCenter` that records instead of notifying, so
//  the reminder tests can assert on what the app *asked* the system for — above
//  all on the permission request it must not make.
//  See docs/workout-reminders.md.
//

import Foundation
import UserNotifications
@testable import GymStreak

@MainActor
final class FakeWorkoutReminderNotificationCenter: WorkoutReminderNotificationCenter {

    /// The status the app reads. Starts undetermined, like a fresh install.
    var status: UNAuthorizationStatus = .notDetermined

    /// What the system prompt would answer.
    var grantsAuthorization = true

    /// How many times the **system** prompt was raised. The number that carries
    /// the pre-prompt's whole reason for existing: a decline must leave it at 0.
    private(set) var authorizationRequestCount = 0

    private(set) var pending: [UNNotificationRequest] = []

    /// Set to make the next `add` throw, standing in for a system refusal.
    var addError: Error?

    func workoutReminderAuthorizationStatus() async -> UNAuthorizationStatus { status }

    func requestWorkoutReminderAuthorization() async throws -> Bool {
        authorizationRequestCount += 1
        status = grantsAuthorization ? .authorized : .denied
        return grantsAuthorization
    }

    func addWorkoutReminderRequest(_ request: UNNotificationRequest) async throws {
        if let addError { throw addError }
        pending.append(request)
    }

    func removePendingWorkoutReminderRequests(withIdentifiers identifiers: [String]) {
        pending.removeAll { identifiers.contains($0.identifier) }
    }

    func pendingWorkoutReminderRequests() async -> [UNNotificationRequest] { pending }

    /// The identifiers currently pending, sorted. They encode the day, so this
    /// is the cheapest readable assertion — and `nextTriggerDate()` is not,
    /// because it resolves against the real clock rather than the test's.
    var pendingIdentifiers: [String] { pending.map(\.identifier).sorted() }

    /// The date components each pending request will fire on, earliest first.
    var pendingTriggerComponents: [DateComponents] {
        pending
            .compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.dateComponents }
            .sorted {
                ($0.year ?? 0, $0.month ?? 0, $0.day ?? 0, $0.hour ?? 0)
                    < ($1.year ?? 0, $1.month ?? 0, $1.day ?? 0, $1.hour ?? 0)
            }
    }

    /// The bodies of everything pending, in the order they were added.
    var pendingBodies: [String] { pending.map(\.content.body) }
}
