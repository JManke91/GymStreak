//
//  UserNotificationReminderPermission.swift
//  GymStreak
//
//  `WorkoutReminderPermissionRequesting` over `UNUserNotificationCenter`.
//  See docs/workout-reminders.md.
//

import Foundation
import UserNotifications

/// The Domain permission gateway, implemented on the notification centre.
///
/// A thin projection rather than a second abstraction: it reuses the same
/// `WorkoutReminderNotificationCenter` seam the scheduler is built on, so the
/// tests drive the real gateway over a faked centre instead of a second double
/// that could drift from it.
@MainActor
final class UserNotificationReminderPermission: WorkoutReminderPermissionRequesting {

    private let notificationCenter: any WorkoutReminderNotificationCenter

    init(
        notificationCenter: any WorkoutReminderNotificationCenter = UNUserNotificationCenter.current()
    ) {
        self.notificationCenter = notificationCenter
    }

    func isReminderPermissionUndetermined() async -> Bool {
        await notificationCenter.workoutReminderAuthorizationStatus() == .notDetermined
    }

    @discardableResult
    func requestReminderPermission() async -> Bool {
        // Swallowed on purpose: `requestAuthorization` throws when the prompt
        // cannot be presented at all, which from the caller's side is the same
        // outcome as a no — the reminders do not start.
        (try? await notificationCenter.requestWorkoutReminderAuthorization()) ?? false
    }
}
