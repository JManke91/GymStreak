//
//  ReviewPromptCoordinator.swift
//  GymStreak
//
//  When to ask the App Store for a rating, and when not to.
//  See docs/rating-prompt.md.
//

import Foundation
import Observation

/// Decides whether the app should ask the system for an App Store review right
/// now, and records that it did.
///
/// It exists as a type of its own, rather than as a `requestReview()` call in a
/// view, because every rule below is a decision and Hard rule 3 keeps decisions
/// out of views. The host does exactly two things: read `isRequestDue` and, when
/// it is true, invoke `@Environment(\.requestReview)` and report back. That is
/// the same split `ProactivePaywallCoordinator` + `ContentView` already use.
///
/// Four rules, all of them here:
///
/// 1. **The fifth completed workout**, counted with the query the app already
///    has (`LifetimeTrainingTotalsProviding.fetchCompletedWorkoutCount()`).
///    There is no rating counter anywhere — see `workoutCount`.
/// 2. **Rule 3** (`docs/monetization-strategy.md` §3). Nothing that interrupts
///    inside an active workout session. A rating alert is an interruption in
///    exactly the way an upsell is, so it is held to the same prohibition.
/// 3. **Never beside a paywall.** A rating prompt stacked on a paywall poisons
///    both, so the ask waits until §8's value-moment placement is no longer owed
///    — see `isValueMomentStillOwed`.
/// 4. **Once, ever**, via `ReviewPromptTracking`.
///
/// **Suppressed is deferred, never consumed.** Nothing is written unless the ask
/// actually goes out, so a completion that hits a rule simply re-attempts at the
/// next one. `isRequestDue` is in-memory only for the same reason: an ask that
/// was decided but never reached the system (the app was killed) is still owed.
///
/// `@Observable` + `@MainActor` and held concretely by the app root, like
/// `FounderCelebrationCoordinator`: the host reads `isRequestDue` in `body`.
@Observable
@MainActor
final class ReviewPromptCoordinator {

    /// Whether the host should invoke `requestReview` now. Written only by this
    /// type; the host reports the ask back through `reviewWasRequested()`.
    private(set) var isRequestDue = false

    /// Completed workouts that earn the automatic rating prompt.
    ///
    /// **The invariant is that this stays strictly above
    /// `ProactivePaywallTrigger.valueMomentWorkoutCount` (3).** §8 placement B
    /// fires at exactly that count, and a rating prompt landing in the same
    /// completion as a paywall poisons both — so the two thresholds are kept
    /// apart by construction rather than arbitrated at runtime.
    /// `reviewPromptThresholdClearsTheValueMoment` pins it.
    ///
    /// Five rather than four is a judgement, not a constraint: by the fifth
    /// session the habit is real enough that the honest answer to "how are you
    /// finding this?" is worth having. Retunable — the only part that is not is
    /// *strictly above three*.
    static let workoutCount = 5

    private let record: any ReviewPromptTracking
    private let totals: any LifetimeTrainingTotalsProviding
    private let paywalls: any PaywallPresenting
    private let activeWorkout: any ActiveWorkoutReporting
    private let workoutCount: Int

    /// - Parameter workoutCount: overridable so the threshold is assertable at a
    ///   boundary other than today's constant, the way
    ///   `ProactivePaywallCoordinator` takes its own.
    init(
        record: any ReviewPromptTracking,
        totals: any LifetimeTrainingTotalsProviding,
        paywalls: any PaywallPresenting,
        activeWorkout: any ActiveWorkoutReporting,
        workoutCount: Int = ReviewPromptCoordinator.workoutCount
    ) {
        self.record = record
        self.totals = totals
        self.paywalls = paywalls
        self.activeWorkout = activeWorkout
        self.workoutCount = workoutCount
    }

    /// A workout was finished and persisted.
    ///
    /// Called from `WorkoutViewModel.completeWorkout` **after**
    /// `ProactivePaywallCoordinator.workoutDidComplete()`, in the same task, so
    /// the two decisions are taken in a fixed order. Rule 3 below does not
    /// actually depend on that order — it asks whether placement B is still
    /// *owed*, which is standing eligibility and is unchanged by B being raised
    /// — but running them in sequence is what lets the no-collision test drive
    /// the real path rather than a scheduling accident.
    func workoutDidComplete() async {
        guard !isRequestDue, !record.hasRequestedReview else { return }
        // Rule 3. Never reached today (`completeWorkout` clears the session
        // first) but kept because it is the prohibition that must not depend on
        // a caller's ordering.
        guard !activeWorkout.isWorkoutActive else { return }
        guard !isValueMomentStillOwed else { return }
        // The count query, not the aggregation: this runs after every completed
        // workout including the ones that cannot meet the threshold, and the two
        // reads share one model actor with the History tab's post-workout
        // refetch (`LifetimeTrainingTotalsProviding`).
        guard let count = try? await totals.fetchCompletedWorkoutCount() else { return }
        // `count` **includes the session that just ended**:
        // `WorkoutViewModel.pauseForCompletion()` stamps `endTime` when the user
        // taps "Finish", before the save screen is even on screen, and
        // `completedCount(in:)` counts every session with an `endTime`. So
        // `>= workoutCount` means "this is the 5th", not "5 happened before this
        // one" — the reading `docs/acquisition-strategy.md` §4.1 asks for, and
        // the same one §8 placement B's `count >= 3` already has. Getting this
        // backwards would be invisible and permanent, because the record below
        // is one-way.
        guard count >= workoutCount else { return }
        isRequestDue = true
    }

    /// Reported by the host once `requestReview` has been invoked.
    ///
    /// **This is where the once-ever is spent.** The system tells the app
    /// nothing about whether an alert appeared, so "we asked" is the only fact
    /// available to record — and it is the right one: retrying because no rating
    /// arrived would ask a user who already rated, which is precisely what
    /// Apple's own throttle exists to prevent.
    func reviewWasRequested() {
        guard isRequestDue else { return }
        isRequestDue = false
        record.recordReviewRequested()
    }

    /// Whether §8 placement B could still be raised.
    ///
    /// The one coupling to the paywall surface, and it is deliberately to the
    /// *standing* eligibility question `PaywallPresenting` already answers for
    /// the onboarding tour, not to the coordinator's private armed state. It
    /// covers more than a same-turn collision: B is deferred, not dropped, when
    /// it cannot be shown, so "already fired" is not the same as "will never
    /// fire". While it is still owed, the rating prompt waits — the paywall is
    /// the moment that has to land cleanly, and the ask costs nothing by waiting
    /// one more workout.
    private var isValueMomentStillOwed: Bool {
        paywalls.isEligible(ProactivePaywallTrigger.valueMoment.placement)
    }
}
