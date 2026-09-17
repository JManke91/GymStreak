//
//  WorkoutReminderNotificationCenter.swift
//  GymStreak
//
//  The training reminders' seam onto `UNUserNotificationCenter`, shaped exactly
//  like the rest timer's. See docs/workout-reminders.md.
//

import Foundation
import UserNotifications

/// What the reminder scheduler and the in-app offer need from the notification
/// centre.
///
/// **A sibling of `RestTimerNotificationCenter`, deliberately not a
/// generalisation of it.** Two small protocols over the same system type cost a
/// few lines of duplication; folding them into one would mean editing shipped
/// rest-timer code — code whose lazy mid-workout authorization request is load-
/// bearing and explicitly out of scope — to serve a retention feature. The
/// duplication is the cheaper of the two.
///
/// The distinct method names exist for the same reason the rest timer's do:
/// `UNUserNotificationCenter` conforms to both protocols, and a shared method
/// name would have one conformance satisfy the other by accident.
@MainActor
protocol WorkoutReminderNotificationCenter: AnyObject {

    /// The current authorization status. `.notDetermined` is the only state in
    /// which the in-app offer is worth showing.
    func workoutReminderAuthorizationStatus() async -> UNAuthorizationStatus

    /// Raises the **system** prompt. Called from exactly one place — the yes
    /// button of the in-app offer.
    func requestWorkoutReminderAuthorization() async throws -> Bool

    func addWorkoutReminderRequest(_ request: UNNotificationRequest) async throws

    func removePendingWorkoutReminderRequests(withIdentifiers identifiers: [String])

    func pendingWorkoutReminderRequests() async -> [UNNotificationRequest]
}

extension UNUserNotificationCenter: WorkoutReminderNotificationCenter {

    func workoutReminderAuthorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }

    func requestWorkoutReminderAuthorization() async throws -> Bool {
        try await requestAuthorization(options: [.alert, .sound])
    }

    func addWorkoutReminderRequest(_ request: UNNotificationRequest) async throws {
        try await add(request)
    }

    func removePendingWorkoutReminderRequests(withIdentifiers identifiers: [String]) {
        removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func pendingWorkoutReminderRequests() async -> [UNNotificationRequest] {
        await pendingNotificationRequests()
    }
}
