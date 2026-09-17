//
//  UserNotificationWorkoutReminderScheduler.swift
//  GymStreak
//
//  Reads the current plans and training history, asks the Domain planner which
//  mornings deserve a reminder or a nudge, and puts exactly those into
//  `UNUserNotificationCenter`.
//  See docs/workout-reminders.md.
//

import Foundation
import OSLog
import UserNotifications

/// Keeps the app's pending training reminders equal to what the plans imply.
///
/// Shaped like `PlannedWorkoutCalendarMirror`, and for the same reason: several
/// unrelated surfaces need the identical three steps — read the plans, ask a
/// pure Domain type what the outside world should hold, hand the answer to a
/// gateway — and none of them should own that glue. Every pass rebuilds the
/// whole window rather than editing it, so nothing here can drift.
///
/// **It never requests authorization.** `RestTimerNotificationCenter`'s
/// scheduler does that lazily mid-workout and keeps doing so, untouched; this
/// one only ever *reads* the status, because the one irreversible system prompt
/// this feature can trigger belongs to the in-app offer the user actually said
/// yes to.
@MainActor
final class UserNotificationWorkoutReminderScheduler: WorkoutReminderScheduling {

    private static let logger = Logger(
        subsystem: "app.gymstreak.reminders",
        category: "PlannedSession"
    )

    /// Every request this app schedules for a training reminder carries this
    /// prefix, so a refresh can retire its own pending requests without ever
    /// touching the rest timer's.
    static let requestIdentifierPrefix = "workoutReminder."

    /// Each kind's own segment after the shared prefix, so identifiers stay
    /// legible in a pending-requests dump. The planner gives every day at most
    /// one kind, so a day still carries at most one request.
    private static func segment(for kind: WorkoutReminderPlanner.Kind) -> String {
        switch kind {
        case .plannedSession: "planned."
        case .missedSession: "missed."
        case .dormancy: "dormancy."
        }
    }

    private let notificationCenter: any WorkoutReminderNotificationCenter
    private let routineRepository: RoutineRepository
    private let workoutSessionRepository: WorkoutSessionRepository
    private let record: any WorkoutReminderTracking
    private let activeWorkout: any ActiveWorkoutReporting
    private let now: () -> Date

    /// Whether a pass is running, and whether one was asked for while it was.
    ///
    /// **The refresh is reentrant otherwise, and reentrancy corrupts the cap.**
    /// Six triggers fire it — launch, foreground, both routine refreshes, both
    /// edges of a workout, and the offer's yes — each as its own `Task`, and the
    /// pass suspends three times. Two overlapping passes would have the second's
    /// unconditional cancellation land after the first had already added
    /// requests, and both would then write a ledger describing neither, which is
    /// how the §10 rating guardrail gets exceeded by one.
    private var isRefreshing = false
    private var isRefreshRequestedAgain = false

    init(
        notificationCenter: any WorkoutReminderNotificationCenter = UNUserNotificationCenter.current(),
        routineRepository: RoutineRepository,
        workoutSessionRepository: WorkoutSessionRepository,
        record: any WorkoutReminderTracking,
        activeWorkout: any ActiveWorkoutReporting,
        now: @escaping () -> Date = Date.init
    ) {
        self.notificationCenter = notificationCenter
        self.routineRepository = routineRepository
        self.workoutSessionRepository = workoutSessionRepository
        self.record = record
        self.activeWorkout = activeWorkout
        self.now = now
    }

    /// Serializes the passes and coalesces the queue.
    ///
    /// A caller that arrives mid-pass books one more pass and returns rather than
    /// waiting: it is a trigger, not a client of the result, and the pass it
    /// booked reads the store fresh. So no trigger is dropped, no two passes
    /// overlap, and a burst of triggers costs at most one extra pass.
    func refreshReminders() async {
        guard !isRefreshing else {
            isRefreshRequestedAgain = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            isRefreshRequestedAgain = false
            await performRefresh()
        } while isRefreshRequestedAgain
    }

    private func performRefresh() async {
        let calendar = HistoryStatsService.isoGermanCalendar()
        let referenceDate = now()

        // Before any early return: the dormancy nudge for a user who never
        // trains measures from the first day the app ran, whether or not it
        // was allowed to speak on that day.
        record.recordFirstSeenIfNeeded(at: referenceDate)

        // Retire this feature's pending requests first, unconditionally. Every
        // early return below is a state in which the app must be *silent*, and
        // a return taken before the cancellation would leave yesterday's plan
        // firing.
        await cancelPendingReminders()

        // Rule 3 (`monetization-strategy.md` §3). Nothing may reach the user
        // while a workout is running — and unlike a paywall, a notification is
        // not something the app can suppress at the moment of delivery once it
        // has been handed to the system. Removing the request is the mechanism.
        // Nothing is written, so the refresh at the end of the workout puts back
        // whatever is still due.
        guard !activeWorkout.isWorkoutActive else { return }

        // Read, never requested — see the type comment.
        guard await notificationCenter.workoutReminderAuthorizationStatus() == .authorized else {
            return
        }

        // The days already spoken for, which the cap is measured against.
        //
        // The test is the **fire moment**, not the day: a reminder that went out
        // at 08:00 this morning has been spoken and still constrains the rest of
        // its rolling window, while everything still ahead of its fire time is
        // about to be re-planned below and counting it would have each pass
        // refuse the schedule it just made. Splitting on the day instead would
        // drop this morning's reminder from the window the moment the user
        // opened the app, which is how a fourth notification in a week gets in.
        // It is exactly complementary to the planner's own candidate filter, so
        // no day is counted twice and none is missed.
        let past = ReminderFrequencyPolicy.prune(
            record.remindedDays.filter { day in
                guard let fireDate = WorkoutReminderPlanner.fireDate(
                    for: day,
                    calendar: calendar
                ) else { return false }
                return fireDate <= referenceDate
            },
            referenceDate: referenceDate,
            calendar: calendar
        )

        let routines = routineRepository.fetchAll()
        // The same bounded per-routine lookup the calendar mirror uses rather
        // than a scan of the whole completed history: this runs on every plan
        // change and every foreground, and history grows forever.
        let lastCompleted = workoutSessionRepository.lastCompletedStartDates(
            forRoutineIds: routines.map(\.id)
        )
        let reminders = WorkoutReminderPlanner.reminders(
            routines: routines,
            lastCompleted: lastCompleted,
            // What withdraws a pending nudge: every completed workout ends in a
            // refresh, and this is the first thing that refresh re-reads.
            lastWorkoutDate: workoutSessionRepository.lastCompletedWorkoutStartDate(),
            firstSeenAt: record.firstSeenAt,
            alreadyReminded: past,
            referenceDate: referenceDate
        )

        var scheduled: [Date] = []
        for reminder in reminders {
            do {
                try await notificationCenter.addWorkoutReminderRequest(
                    makeRequest(for: reminder, calendar: calendar)
                )
                scheduled.append(reminder.day)
            } catch {
                // Swallowed like the calendar mirror's failures: the plan is
                // saved and correct, a reminder is a projection of it, and the
                // next refresh rebuilds the whole window anyway.
                Self.logger.error(
                    "Reminder could not be scheduled: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        // Past days are kept — they are what the rolling window is made of —
        // and the future is replaced by what this pass actually managed to
        // schedule, so a failed request does not spend a day's allowance.
        record.setRemindedDays(past + scheduled)
    }

    // MARK: - Requests

    private func cancelPendingReminders() async {
        let identifiers = await notificationCenter.pendingWorkoutReminderRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.requestIdentifierPrefix) }
        guard !identifiers.isEmpty else { return }
        notificationCenter.removePendingWorkoutReminderRequests(withIdentifiers: identifiers)
    }

    private func makeRequest(
        for reminder: WorkoutReminderPlanner.Reminder,
        calendar: Calendar
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        switch reminder.kind {
        case .plannedSession:
            content.title = "notification.planned_session.title".localized
            content.body = reminder.routineName.map {
                "notification.planned_session.body_routine".localized($0)
            } ?? "notification.planned_session.body".localized
        case .missedSession:
            content.title = "notification.missed_session.title".localized
            content.body = reminder.routineName.map {
                "notification.missed_session.body_routine".localized($0)
            } ?? "notification.missed_session.body".localized
        case .dormancy:
            content.title = "notification.dormancy.title".localized
            content.body = "notification.dormancy.body".localized
        }
        content.sound = .default

        // A calendar trigger on the full date, not a time interval: the fire
        // date is a wall-clock morning, and the user may cross a time zone
        // between scheduling and delivery.
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminder.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        return UNNotificationRequest(
            identifier: Self.identifier(for: reminder.day, kind: reminder.kind, calendar: calendar),
            content: content,
            trigger: trigger
        )
    }

    /// One identifier per day, so a day can never carry two reminder requests
    /// however many times a pass runs.
    ///
    /// The day is rendered from `Calendar` components rather than a
    /// `DateFormatter`, for the reason `PlannedWorkoutMarker` gives: a hoisted
    /// formatter caches its time zone and would silently shift the identifier by
    /// a day for a user who travels.
    static func identifier(
        for day: Date,
        kind: WorkoutReminderPlanner.Kind,
        calendar: Calendar
    ) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        let dayString = String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0
        )
        return requestIdentifierPrefix + segment(for: kind) + dayString
    }
}
