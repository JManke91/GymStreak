//
//  WorkoutReminderStore.swift
//  GymStreak
//
//  The durable half of training reminders: the in-app offer's record and the
//  frequency cap's ledger. See docs/workout-reminders.md.
//

import Foundation

/// `UserDefaults`-backed conformer for `WorkoutReminderTracking`.
///
/// Plain `UserDefaults.standard`, matching `OnboardingCompletionStore` and
/// `ReviewPromptStore` — the reasoning against iCloud KVS and against the App
/// Group suite is on the protocol. Both halves are cached in memory and seeded
/// at init, because both are read on paths that must not touch disk repeatedly:
/// the offer's record while the app root is being composed, the ledger on every
/// refresh.
@MainActor
final class WorkoutReminderStore: WorkoutReminderTracking {

    private(set) var reminderOfferCount: Int
    private(set) var lastReminderOfferDeclinedAt: Date?
    private(set) var hasAcceptedReminderOffer: Bool
    private(set) var remindedDays: [Date]
    private(set) var firstSeenAt: Date?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.reminderOfferCount = defaults.integer(forKey: Self.offerCountKey)
        self.lastReminderOfferDeclinedAt = defaults.object(forKey: Self.declinedAtKey) as? Date
        self.hasAcceptedReminderOffer = defaults.bool(forKey: Self.acceptedKey)
        self.remindedDays = (defaults.array(forKey: Self.remindedDaysKey) as? [Date]) ?? []
        self.firstSeenAt = defaults.object(forKey: Self.firstSeenKey) as? Date
    }

    func recordReminderOfferAccepted() {
        guard !hasAcceptedReminderOffer else { return }
        hasAcceptedReminderOffer = true
        reminderOfferCount += 1
        defaults.set(true, forKey: Self.acceptedKey)
        defaults.set(reminderOfferCount, forKey: Self.offerCountKey)
    }

    func recordReminderOfferDeclined(at date: Date) {
        lastReminderOfferDeclinedAt = date
        reminderOfferCount += 1
        defaults.set(date, forKey: Self.declinedAtKey)
        defaults.set(reminderOfferCount, forKey: Self.offerCountKey)
    }

    func setRemindedDays(_ days: [Date]) {
        remindedDays = days
        defaults.set(days, forKey: Self.remindedDaysKey)
    }

    func recordFirstSeenIfNeeded(at date: Date) {
        guard firstSeenAt == nil else { return }
        firstSeenAt = date
        defaults.set(date, forKey: Self.firstSeenKey)
    }

    private static let offerCountKey = "reminders.offerCount"
    private static let declinedAtKey = "reminders.offerDeclinedAt"
    private static let acceptedKey = "reminders.offerAccepted"
    private static let remindedDaysKey = "reminders.remindedDays"
    private static let firstSeenKey = "reminders.firstSeenAt"
}
