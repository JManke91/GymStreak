import Foundation

/// What the Lock Screen / Dynamic Island countdown needs to know about one
/// rest timer. Deliberately ActivityKit-free so `Domain/` and `Presentation/`
/// stay unaware of the framework — only `Data/LiveActivity` imports it.
struct RestTimerLiveActivityContent: Equatable {
    /// Shown as the activity's fixed title. The routine's name, or a fallback
    /// when the timer is running outside a routine-backed session.
    let workoutName: String
    /// The exercise the user is resting from, when one is known.
    let exerciseName: String?
    /// Countdown bounds. `deadline` is authoritative — the same absolute date
    /// the in-app countdown and the local notification are derived from — and
    /// doubles as the activity's stale date.
    let startDate: Date
    let deadline: Date
}

/// The rest timer's Lock Screen / Dynamic Island surface, as a system gateway.
///
/// Mirrors `RestTimerReminderScheduling`: identity-keyed, so one instance can
/// be shared by both `WorkoutViewModel`s without one of them ending the
/// other's countdown. The timer's UUID is the same one the notification
/// scheduler and the persisted timer state use.
@MainActor
protocol RestTimerLiveActivityPresenting {
    /// Presents the countdown for `id`, or leaves it in place if `id` is
    /// already being presented. Presenting a *different* id replaces the
    /// current one. A no-op when the user has Live Activities turned off.
    func startActivity(id: UUID, content: RestTimerLiveActivityContent)

    /// Ends `id`'s countdown, briefly showing a completion state. Does nothing
    /// if `id` is not the presented timer.
    func endActivity(id: UUID)

    /// Ends countdowns left behind by an earlier app process whose deadline has
    /// already passed. Safe to call repeatedly.
    func dismissExpiredActivities()
}
