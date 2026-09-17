//
//  WorkoutReminderTracking.swift
//  GymStreak
//
//  The durable state behind training reminders: whether the in-app offer has
//  been made, and which days already carry a reminder.
//  See docs/workout-reminders.md.
//

import Foundation

/// What the app remembers about reminding this user.
///
/// **One protocol for both halves rather than two.** They are one feature's
/// durable state, they are written by the same two collaborators, and splitting
/// them would double the composition-root wiring without making either half
/// safer — the same trade `ActiveWorkoutReporting` makes for its read and write.
///
/// Device-local `UserDefaults`, never iCloud KVS and never the App Group suite,
/// for the reasons `OnboardingCompletionTracking` sets out: notification
/// authorization is a per-device fact, so a record mirrored across devices would
/// suppress the offer on a device that has never asked. The watch shows no
/// reminders and reads none of this.
@MainActor
protocol WorkoutReminderTracking: AnyObject {

    // MARK: - The in-app offer

    /// How many times the in-app offer has been shown and answered. Bounded by
    /// `WorkoutReminderOptInViewModel.maxOffers` — a decline may be revisited
    /// once, not forever.
    var reminderOfferCount: Int { get }

    /// When the user last said no to the in-app offer, if they have.
    var lastReminderOfferDeclinedAt: Date? { get }

    /// Whether the user has said yes. One-way: nothing ever un-accepts, because
    /// the answer that matters after a yes is the system's, not ours.
    var hasAcceptedReminderOffer: Bool { get }

    /// Records a yes. Spent when the offer is *answered*, not when it is raised.
    func recordReminderOfferAccepted()

    /// Records a no, with the moment it happened so the re-offer cooldown can be
    /// measured from it.
    func recordReminderOfferDeclined(at date: Date)

    // MARK: - The frequency-cap ledger

    /// The days that already carry a reminder — past deliveries and the pending
    /// future alike. Read by `ReminderFrequencyPolicy` and by nothing else.
    ///
    /// A *scheduled* day whose fire time has passed is treated as delivered.
    /// The app cannot know whether a notification was actually seen, and for a
    /// cap whose purpose is to bound how often the app speaks, having spoken is
    /// the fact that matters.
    var remindedDays: [Date] { get }

    /// Replaces the ledger wholesale. The scheduler owns the merge — it is the
    /// only party that knows which days it just re-planned.
    func setRemindedDays(_ days: [Date])

    // MARK: - The dormancy anchor

    /// When the reminder scheduler first ran on this device — the install-date
    /// stand-in the dormancy nudge measures from for a user who has never
    /// completed a workout. Nothing else in the app records an install date.
    /// For a user updating from a build without it, this is the update day,
    /// which errs toward nudging later rather than at once.
    var firstSeenAt: Date? { get }

    /// Records `date` as `firstSeenAt` unless one is already recorded.
    func recordFirstSeenIfNeeded(at date: Date)
}
