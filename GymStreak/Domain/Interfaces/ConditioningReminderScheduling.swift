//
//  ConditioningReminderScheduling.swift
//  GymStreak
//
//  "Remind me later" for a hard conditioning session the post-workout add-on
//  advised against starting straight after lifting.
//  See docs/fight-conditioning.md and docs/workout-reminders.md.
//

import Foundation

/// The one pending conditioning reminder.
///
/// Deliberately **not** routed through `WorkoutReminderScheduling`. That
/// scheduler *derives* a window of mornings from the user's plans and rebuilds
/// it on every pass; this is a single, user-requested, one-shot reminder for a
/// moment that exists nowhere in the plans. Folding it in would mean teaching
/// the planner about state it cannot re-derive, and the first rebuild would
/// silently drop it.
///
/// It also does not go through `ReminderFrequencyPolicy`, for the reason the
/// rest timer and the conditioning cues do not: that cap bounds how often the
/// app speaks **unprompted**. This reminder exists because the user asked for
/// it, one tap ago. Its own cap is structural instead — one identifier, so a
/// second request replaces the first and at most one can ever be pending.
///
/// The copy is passed in already localized: the vocabulary lives in
/// `ConditioningCopy` (Presentation), and `Data/` has no business reaching it.
@MainActor
protocol ConditioningReminderScheduling: AnyObject {

    /// Replaces the pending conditioning reminder with one firing at `date`.
    ///
    /// Returns whether it was actually scheduled. It is `false` when
    /// notification permission is not granted — **this never asks for it**, for
    /// the reason `WorkoutReminderScheduling` never does: the one irreversible
    /// system prompt belongs to a caller the user can see.
    @discardableResult
    func scheduleConditioningReminder(title: String, body: String, at date: Date) async -> Bool

    /// Withdraws the pending conditioning reminder, if there is one.
    func cancelConditioningReminder()
}
