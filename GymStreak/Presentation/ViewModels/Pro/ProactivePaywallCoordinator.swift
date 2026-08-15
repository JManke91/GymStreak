//
//  ProactivePaywallCoordinator.swift
//  GymStreak
//
//  §8's two proactive placements: when A and B have happened, and when it is
//  safe to say so. See docs/pro-subscription.md §5g.
//

import Foundation
import Observation

/// Decides *when* §8's placements A and B have arrived, and raises them at a
/// moment the app is allowed to show a paywall.
///
/// Everything about *whether* a raised placement becomes a visible paywall still
/// belongs to `PaywallPresenter` — the kill switch, the entitlement, Rule 3 and
/// the once-ever cap are all enforced there and are not re-implemented here.
/// What this type adds is the one thing the presenter cannot know: that a
/// condition became **true** at a moment when nothing could be shown.
///
/// **Suppressed is deferred, never consumed.** The value moment can become true
/// mid-session — the third workout completes, an overload suggestion appears —
/// and Rule 3 forbids a paywall there. The presenter drops such a request
/// (`show(_:)` returns without setting anything) and, because the once-ever
/// record is only written on `didPresent`, nothing is spent. The armed flag in
/// `ProactivePaywallTracking` is what turns that drop into a deferral: it
/// survives the session and the launch, and every session end re-attempts.
///
/// It is its own type rather than methods on `WorkoutViewModel` for the reason
/// `AICoachAllowanceGate` is: the ViewModels that report the events are
/// untestable in isolation (HealthKit, a live `ModelContext`), while every
/// acceptance criterion here is about *what is armed and what is raised*, which
/// is assertable directly.
///
/// `@Observable` because the host renders `valueMomentTotals` inside the paywall
/// sheet; `@MainActor` like the rest of the Pro surface.
@Observable
@MainActor
final class ProactivePaywallCoordinator {

    /// The endowed figures placement B shows. Non-`nil` by the time
    /// `.valueMoment` is ever raised — B is not raised at all until they load,
    /// because a value-moment paywall without the user's own numbers is just a
    /// paywall (§8 B).
    private(set) var valueMomentTotals: LifetimeTrainingTotals?

    private let entitlements: any ProEntitlementProviding
    private let paywalls: any PaywallPresenting
    private let triggers: any ProactivePaywallTracking
    private let totals: any LifetimeTrainingTotalsProviding
    private let activeWorkout: any ActiveWorkoutReporting
    private let isGatingEnabled: Bool
    private let valueMomentWorkoutCount: Int

    /// - Parameters:
    ///   - isGatingEnabled: injected rather than read from `ProGating` inside
    ///     the checks, for the same reason `PaywallPresenter` and
    ///     `AICoachAllowanceGate` inject it: with the shipped switch baked in,
    ///     every test would pass by proving the coordinator is inert.
    ///   - valueMomentWorkoutCount: overridable so §8 B's threshold is
    ///     assertable at a boundary other than today's constant.
    init(
        entitlements: any ProEntitlementProviding,
        paywalls: any PaywallPresenting,
        triggers: any ProactivePaywallTracking,
        totals: any LifetimeTrainingTotalsProviding,
        activeWorkout: any ActiveWorkoutReporting,
        isGatingEnabled: Bool = ProGating.isEnabled,
        valueMomentWorkoutCount: Int = ProactivePaywallTrigger.valueMomentWorkoutCount
    ) {
        self.entitlements = entitlements
        self.paywalls = paywalls
        self.triggers = triggers
        self.totals = totals
        self.activeWorkout = activeWorkout
        self.isGatingEnabled = isGatingEnabled
        self.valueMomentWorkoutCount = valueMomentWorkoutCount
    }

    // MARK: - Events
    //
    // All four are `async` and the callers wrap them in a `Task`, rather than
    // each spawning one internally. Placement B cannot decide anything without
    // first reading the history off the main actor, so the work is genuinely
    // asynchronous — hiding that behind a fire-and-forget `Task` would leave the
    // acceptance criteria (the one-shot, the deferral, whichever-comes-first)
    // only assertable by yielding and hoping.

    /// A routine template was saved.
    ///
    /// **The first creation event this install observes arms A**, not "the
    /// user's first routine". §8 words the trigger as the creation event, and
    /// the narrower reading would leave A permanently dead for everyone who
    /// already had routines when gating flipped on — which, since the switch
    /// ships off until ticket 15, is the entire existing user base.
    func routineWasCreated() async {
        arm(.firstRoutineCreated)
        await raiseNextArmedTrigger()
    }

    /// An automatic progressive-overload suggestion was put on screen — the
    /// mid-workout prompt bar or the completion screen's card.
    ///
    /// Always inside a session, so this effectively only ever *arms*; the raise
    /// happens when the session ends. That is the deferral, exercised on every
    /// single occurrence rather than on a rare edge case.
    func overloadSuggestionWasShown() async {
        arm(.valueMoment)
        await raiseNextArmedTrigger()
    }

    /// A workout was finished and persisted. Call **after** the session has been
    /// cleared, so Rule 3 no longer suppresses.
    func workoutDidComplete() async {
        // The session that just ended moved all three figures, so anything read
        // earlier in this process is stale. Placement B's whole persuasive
        // content is that the numbers are correct.
        valueMomentTotals = nil
        await armValueMomentIfEarned()
        await raiseNextArmedTrigger()
    }

    /// A workout ended without being completed (discarded). Raises nothing new —
    /// it only gives a trigger deferred by Rule 3 its next safe moment.
    func activeWorkoutDidEnd() async {
        await raiseNextArmedTrigger()
    }

    // MARK: - Arming

    private func arm(_ trigger: ProactivePaywallTrigger) {
        guard isEligible(trigger) else { return }
        triggers.arm(trigger)
    }

    /// Arms B when the completed-workout count has reached §8 B's threshold.
    ///
    /// **The threshold is decided by a counting query, not by the aggregation.**
    /// This runs after every completed workout, including the ones that provably
    /// cannot meet the threshold, and the two reads share one model actor with
    /// the History tab's post-workout refetch — so the expensive one is deferred
    /// to the moment B is actually raised. The figures are still a whole,
    /// separate read of the same store taken milliseconds later; they can only
    /// disagree with this count if another workout landed in between (watch
    /// sync), which makes the shown numbers *more* current, never wrong.
    private func armValueMomentIfEarned() async {
        guard isEligible(.valueMoment), !triggers.isArmed(.valueMoment) else { return }
        guard let count = try? await totals.fetchCompletedWorkoutCount() else { return }
        guard count >= valueMomentWorkoutCount else { return }
        triggers.arm(.valueMoment)
    }

    // MARK: - Raising

    /// Raises **one** armed placement, or nothing.
    ///
    /// One per turn because the presenter replaces a request that has not yet
    /// reached the screen: raising A and B back to back would drop A. Whatever
    /// is not raised stays armed for the next safe moment.
    private func raiseNextArmedTrigger() async {
        // Rule 3 belongs to the presenter and is enforced there; this is not a
        // second copy of it but a guard on the *work*. Without it, an overload
        // suggestion appearing mid-set would run a whole-history aggregation to
        // feed a paywall that cannot appear, inside the one part of the app
        // where nothing may compete for resources.
        guard !activeWorkout.isWorkoutActive else { return }
        for trigger in ProactivePaywallTrigger.flushOrder {
            guard isEligible(trigger), triggers.isArmed(trigger) else { continue }
            if trigger == .valueMoment, await loadValueMomentTotals() == nil {
                // The figures could not be read. B stays armed and is retried
                // at the next session end — showing it with no numbers, or with
                // placeholder ones, is worse than showing nothing (§8 B).
                continue
            }
            paywalls.present(trigger.placement)
            return
        }
    }

    // MARK: - Figures

    /// The all-time totals, read once per process unless a completed workout
    /// invalidates them.
    ///
    /// `nil` on a failed read, which every caller treats as "not now" rather
    /// than as zeroes.
    private func loadValueMomentTotals() async -> LifetimeTrainingTotals? {
        if let valueMomentTotals { return valueMomentTotals }
        // `@concurrent` on the conformer is what keeps this unbounded fetch off
        // the main actor (docs/swift6-concurrency.md §1).
        valueMomentTotals = try? await totals.fetchLifetimeTotals()
        return valueMomentTotals
    }

    // MARK: - Eligibility

    /// The cheap half of eligibility, asked here as well as in the presenter.
    ///
    /// Not a duplicated rule but a *guard on the work*: without it, every
    /// workout completion of every user — including all of them while the kill
    /// switch is off — would run an unbounded fetch over the whole history to
    /// feed a paywall the presenter is going to refuse anyway.
    private func isEligible(_ trigger: ProactivePaywallTrigger) -> Bool {
        isGatingEnabled
            && !entitlements.isPro
            && !paywalls.hasPresented(trigger.placement)
    }
}
