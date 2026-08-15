//
//  ProactivePaywallTrigger.swift
//  GymStreak
//
//  The two §8 placements that fire on their own rather than on a blocked action.
//  See docs/monetization-strategy.md §8 A and B, and docs/pro-subscription.md §5g.
//

import Foundation

/// A paywall moment the *app* decides has arrived, as opposed to one the user
/// walked into by tapping a gated affordance.
///
/// Deliberately not the same type as `PaywallPlacement`: a placement is "where a
/// paywall came from" and there are nine of them, while this is "a condition the
/// app watches for" and there are exactly two. Modelling them as their own enum
/// is what makes it impossible to arm a contextual gate — `.routineCap` has no
/// condition to become true, it is simply raised at the moment it is refused.
///
/// `rawValue` is a **storage key**: it is what the armed flag is filed under in
/// `UserDefaults`. Renaming a case does not fail — it silently disarms a trigger
/// that was already waiting, which is why the raw values are written out rather
/// than derived from the case name.
enum ProactivePaywallTrigger: String, CaseIterable, Sendable {

    /// §8 A — the soft, dismissible placement. Armed by the first routine
    /// creation this install observes.
    case firstRoutineCreated = "first-routine-created"

    /// §8 B — the endowed-progress value moment. Armed by the third completed
    /// workout **or** the first automatic progressive-overload suggestion,
    /// whichever lands first.
    case valueMoment = "value-moment"

    /// The placement this trigger raises. Both are one-shot, so the once-ever
    /// record `PaywallPresenter` already keeps is what stops a second firing —
    /// this type never has to count.
    var placement: PaywallPlacement {
        switch self {
        case .firstRoutineCreated: .firstRoutineCreated
        case .valueMoment: .valueMoment
        }
    }

    /// Where the armed flag is filed. Namespaced under `pro.` like every other
    /// monetization key, and distinct from `pro.paywallPresented.<id>` — armed
    /// and presented are genuinely different facts (§5g).
    var storageKey: String { "pro.trigger.\(rawValue)" }

    /// Completed workouts that earn the value moment on their own (§8 B: "after
    /// the 3rd completed workout").
    ///
    /// Lives here rather than in `ProFeatureCaps` because it is not a free-tier
    /// limit — nothing is capped at three workouts — but it is retunable for the
    /// same §9 reason every cap is, so it stays a named constant in one place.
    static let valueMomentWorkoutCount = 3

    /// The order `ProactivePaywallCoordinator` considers armed triggers in.
    ///
    /// One placement is raised per flush, never two: the presenter replaces a
    /// request that has not yet reached the screen (§5a), so raising both in the
    /// same turn would silently drop the first. The value moment goes first
    /// because §8 calls it the highest-value placement in the app; the soft one
    /// keeps its armed record and is raised at the next safe moment.
    static let flushOrder: [ProactivePaywallTrigger] = [.valueMoment, .firstRoutineCreated]
}
