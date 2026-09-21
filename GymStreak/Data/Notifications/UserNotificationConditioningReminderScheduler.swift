//
//  UserNotificationConditioningReminderScheduler.swift
//  GymStreak
//
//  `ConditioningReminderScheduling` over `UNUserNotificationCenter`, through the
//  training reminders' existing seam. See docs/fight-conditioning.md.
//

import Foundation
import UserNotifications

/// The one pending conditioning reminder, on the notification centre.
///
/// It reuses `WorkoutReminderNotificationCenter` rather than declaring a third
/// protocol over the same system type: this needs exactly the four operations
/// that seam already exposes, and a fake of it already exists in the tests.
///
/// **Its identifier does not carry the `workoutReminder.` prefix**, which is
/// what keeps the two features from deleting each other's requests:
/// `UserNotificationWorkoutReminderScheduler.cancelPendingReminders` retires
/// only that prefix, so a reminder scheduled here survives every plan refresh —
/// and this class in turn never touches a training reminder.
@MainActor
final class UserNotificationConditioningReminderScheduler: ConditioningReminderScheduling {

    /// One identifier, so a second "remind me later" replaces the first and at
    /// most one conditioning reminder can ever be pending. That is this
    /// feature's whole frequency cap — see `ConditioningReminderScheduling`.
    static let requestIdentifier = "conditioning.reminder.session"

    private let notificationCenter: any WorkoutReminderNotificationCenter
    private let calendar: Calendar

    init(
        notificationCenter: any WorkoutReminderNotificationCenter = UNUserNotificationCenter.current(),
        calendar: Calendar = .current
    ) {
        self.notificationCenter = notificationCenter
        self.calendar = calendar
    }

    @discardableResult
    func scheduleConditioningReminder(title: String, body: String, at date: Date) async -> Bool {
        // Unconditionally first, like the training reminders' own pass: every
        // return below is a state in which no conditioning reminder should be
        // pending, including the one where permission turns out to be missing.
        cancelConditioningReminder()
        guard await notificationCenter.workoutReminderAuthorizationStatus() == .authorized else { return false }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // Components, not a time interval: the reminder is a wall-clock moment,
        // and one pushed to tomorrow morning must still land at 08:00 after a
        // DST change or a flight.
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let request = UNNotificationRequest(
            identifier: Self.requestIdentifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )

        do {
            try await notificationCenter.addWorkoutReminderRequest(request)
            return true
        } catch {
            print("Conditioning reminder could not be scheduled: \(error)")
            return false
        }
    }

    func cancelConditioningReminder() {
        notificationCenter.removePendingWorkoutReminderRequests(withIdentifiers: [Self.requestIdentifier])
    }
}
