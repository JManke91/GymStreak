//
//  WorkoutReminderOptInViewModel.swift
//  GymStreak
//
//  Whether to offer training reminders, and what a yes actually does.
//  See docs/workout-reminders.md.
//

import Foundation
import Observation

/// The soft pre-prompt in front of the iOS notification permission.
///
/// **The pre-prompt is the feature, not decoration.** A denial of the system
/// prompt is permanent and unrecoverable in-app — the user has to go to
/// Settings — so the app gets exactly one ask. Spending it on a cold prompt at
/// launch, in the session most users never return from, converts a retention
/// lever into another reason to leave. A no to *this* screen costs no
/// permission at all, which is what makes asking again later possible.
///
/// Same shape as `FounderCelebrationCoordinator`: an `@Observable` flag the app
/// root binds a `.fullScreenCover` to, with every eligibility rule in one type
/// rather than spread across the host. Five rules, all of them here:
///
/// 1. **Only while the system has not been asked**
///    (`WorkoutReminderPermissionRequesting.isReminderPermissionUndetermined()`).
///    A user who already granted permission — the
///    rest timer asks for it lazily, mid-workout, and that request is untouched
///    by this feature — is never asked again; their reminders simply start
///    working. A user who already denied it cannot be helped by an in-app
///    screen, and showing them one is nagging.
/// 2. **Never more than `maxOffers` times**, so a decline can be revisited once
///    and then never again.
/// 3. **Not within `reofferCooldownDays` of a decline.**
/// 4. **Never inside an active workout** (`monetization-strategy.md` §3 Rule 3)
///    — a full-screen cover is an interruption whether or not it sells anything.
/// 5. **Never during the first-run tour**, which `FirstRunCoverOrder` enforces
///    by ordering rather than by a condition here: the offer is raised at launch
///    and simply becomes the topmost cover once the tour ends.
///
/// **Suppressed is deferred, never consumed.** Nothing is written until the user
/// answers, so an offer that never reached the screen is still owed.
@Observable
@MainActor
final class WorkoutReminderOptInViewModel {

    /// How many times the in-app offer may be made. Two: once for the user who
    /// was not ready on day one, and never again — a third ask is the app not
    /// taking no for an answer, and §10's rating guardrail outranks the lever.
    static let maxOffers = 2

    /// How long after a decline the offer may be made again. Two weeks is long
    /// enough that the second ask lands in a different frame of mind than the
    /// first, and short enough to still reach a user inside the window this
    /// lever exists to move.
    static let reofferCooldownDays = 14

    /// Whether the offer should be on screen. Written only by this type; the
    /// host reports a dismissal back through `offerWasDismissed()`.
    private(set) var isPresenting = false

    private let record: any WorkoutReminderTracking
    /// The narrow Domain projection of the system permission — never the
    /// notification centre itself, which lives in `Data/`.
    private let permission: any WorkoutReminderPermissionRequesting
    private let scheduler: any WorkoutReminderScheduling
    private let activeWorkout: any ActiveWorkoutReporting
    private let now: () -> Date

    init(
        record: any WorkoutReminderTracking,
        permission: any WorkoutReminderPermissionRequesting,
        scheduler: any WorkoutReminderScheduling,
        activeWorkout: any ActiveWorkoutReporting,
        now: @escaping () -> Date = Date.init
    ) {
        self.record = record
        self.permission = permission
        self.scheduler = scheduler
        self.activeWorkout = activeWorkout
        self.now = now
    }

    /// Raises the offer if it is due and the moment is a safe one.
    ///
    /// Called at two deterministic moments, exactly like
    /// `FounderCelebrationCoordinator.presentIfDue()`: once from the launch task
    /// (so a fresh install meets it the moment the tour ends) and on every
    /// foreground (so an offer a rule suppressed, or a cooldown that has since
    /// elapsed, arrives without waiting for a relaunch). Both are idempotent.
    func presentIfDue() async {
        guard !isPresenting, isOfferDue else { return }
        // Asked last, because it is the only rule that costs a round-trip to the
        // notification centre.
        guard await permission.isReminderPermissionUndetermined() else { return }
        // Re-checked after the await: a workout can start, and the offer can be
        // answered, while the status query is in flight.
        guard !isPresenting, isOfferDue else { return }
        isPresenting = true
    }

    /// The user said yes: raise the **system** prompt, then get out of the way.
    ///
    /// The cover stays up until the system alert has been answered, deliberately.
    /// Dismissing first would let the next first-run cover slide in underneath
    /// an alert the user is still reading.
    func accept() async {
        guard isPresenting else { return }
        // Recorded before the prompt, not after: the offer has been answered
        // whatever the system alert returns, and a user who is killed mid-alert
        // must not be offered it again.
        record.recordReminderOfferAccepted()
        await permission.requestReminderPermission()
        isPresenting = false
        // Whether or not permission was granted — the scheduler reads the status
        // itself and schedules nothing without it.
        await scheduler.refreshReminders()
    }

    /// The user said not now. Costs no system permission, which is the entire
    /// point of the screen.
    func decline() {
        guard isPresenting else { return }
        isPresenting = false
        record.recordReminderOfferDeclined(at: now())
    }

    /// Reported by the host when the cover has gone away.
    ///
    /// Idempotent and guarded, so the dismissal SwiftUI writes back after
    /// `accept()` or `decline()` already lowered the flag records nothing a
    /// second time. It is also the backstop for a dismissal this type did not
    /// initiate, which is read as a decline — the user closed the screen without
    /// saying yes.
    func offerWasDismissed() {
        decline()
    }

    /// The rules that do not need to touch the notification centre.
    private var isOfferDue: Bool {
        guard !record.hasAcceptedReminderOffer else { return false }
        guard record.reminderOfferCount < Self.maxOffers else { return false }
        guard !activeWorkout.isWorkoutActive else { return false }
        guard let declinedAt = record.lastReminderOfferDeclinedAt else { return true }
        let calendar = HistoryStatsService.isoGermanCalendar()
        guard let earliestReoffer = calendar.date(
            byAdding: .day,
            value: Self.reofferCooldownDays,
            to: calendar.startOfDay(for: declinedAt)
        ) else { return false }
        return now() >= earliestReoffer
    }
}
