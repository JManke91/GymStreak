//
//  WorkoutReminderPermissionRequesting.swift
//  GymStreak
//
//  The two questions the in-app reminder offer needs answered about notification
//  permission, with no notification framework in the signature.
//  See docs/workout-reminders.md.
//

import Foundation

/// The system notification permission, as much of it as Presentation may see.
///
/// It exists as a Domain gateway rather than letting the offer's view model hold
/// `WorkoutReminderNotificationCenter` directly, because that protocol lives in
/// `Data/Notifications/` and Presentation depends on Domain protocols only. The
/// projection is deliberately narrow — two questions, no `UNAuthorizationStatus`
/// — so `Domain/Interfaces/` stays Foundation-only and no ViewModel can reach a
/// notification API it has no business calling.
///
/// **`requestReminderPermission()` is the one place in this feature that may
/// raise the system prompt**, and the only caller is the yes button of the
/// in-app offer. The scheduler reads the status and never asks (see
/// `WorkoutReminderScheduling`).
@MainActor
protocol WorkoutReminderPermissionRequesting: AnyObject {

    /// Whether the system has never been asked. The only state in which the
    /// in-app offer is worth showing: already granted means there is nothing to
    /// ask for, and already denied cannot be undone from inside the app.
    func isReminderPermissionUndetermined() async -> Bool

    /// Raises the system prompt and reports whether it was granted. A refusal to
    /// even present is reported as "not granted" — from the caller's side there
    /// is nothing to distinguish and nothing to do differently.
    @discardableResult
    func requestReminderPermission() async -> Bool
}
