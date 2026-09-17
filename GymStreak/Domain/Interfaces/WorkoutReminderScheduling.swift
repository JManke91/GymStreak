//
//  WorkoutReminderScheduling.swift
//  GymStreak
//
//  The seam every trigger uses to bring the training reminders back in line
//  with the user's plans. See docs/workout-reminders.md.
//

import Foundation

/// Rebuilds the app's pending training reminders from the current plans.
///
/// One method, because there is one operation: the schedule is **derived**, not
/// incrementally edited. Every trigger — a plan changed, a workout finished, the
/// app came back to the foreground, permission was just granted — asks the same
/// question, and answering it from scratch is what keeps the reminder and the
/// Verlauf tab from drifting apart.
///
/// It is also the mechanism behind "never during an active workout": a refresh
/// taken while a workout is running clears the pending reminders and schedules
/// nothing, and the refresh at the end of the workout puts back whatever is
/// still due. Suppressing the *presentation* of a notification is only possible
/// in the foreground; removing the request is possible always.
///
/// **It never asks for permission.** The system prompt belongs to the in-app
/// offer alone (`WorkoutReminderOptInViewModel`) — a scheduler that requested
/// authorization would spend the user's one irreversible answer on a background
/// refresh they never saw.
@MainActor
protocol WorkoutReminderScheduling: AnyObject {

    /// Cancels the app's pending training reminders and re-derives them.
    /// Idempotent, and safe to call from any number of triggers.
    func refreshReminders() async
}
