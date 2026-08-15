//
//  ProactivePaywallTracking.swift
//  GymStreak
//
//  How the app remembers that a §8 A/B trigger became true, without knowing
//  where that fact is stored. See docs/pro-subscription.md §5g.
//

import Foundation

/// The durable "this trigger has become true" record for §8's two proactive
/// placements.
///
/// **Armed is not presented, and keeping the two apart is the whole point of
/// this protocol.** `PaywallPresenter` already records what has been *shown*
/// (once ever, on `didPresent`). What it cannot record is a condition that came
/// true at a moment when nothing may be shown — Rule 3's absolute prohibition
/// inside a workout is exactly that case, and §8's value moment is exactly the
/// trigger most likely to arrive there. Without this record the request would be
/// dropped and placement B would never fire again for that user.
///
/// Arming is one-way: a trigger that has become true stays true, so the deferral
/// survives a relaunch. Nothing ever disarms it — the presenter's once-ever
/// record is what ends the trigger's life.
///
/// `@MainActor` like the rest of the Pro protocol surface, and it imports
/// nothing beyond Foundation on purpose: no `UserDefaults` suite name may appear
/// in this signature.
@MainActor
protocol ProactivePaywallTracking: AnyObject {

    /// Whether `trigger`'s condition has already been observed on this install.
    ///
    /// Cheap by contract — the coordinator asks on every workout completion, so
    /// a conformer answers from memory rather than from I/O.
    func isArmed(_ trigger: ProactivePaywallTrigger) -> Bool

    /// Records that `trigger`'s condition became true. Idempotent.
    func arm(_ trigger: ProactivePaywallTrigger)
}

#if DEBUG
/// Debug-only counterpart to `PaywallPresentationDebugging.resetPresentedPlacements()`.
///
/// Resetting the once-ever record without also disarming the triggers would
/// leave A and B firing again at the next event — which looks like the reset
/// worked, but proves nothing about the triggers themselves.
@MainActor
protocol ProactivePaywallTrackingDebugging: ProactivePaywallTracking {

    /// Forgets every armed trigger, so A and B can be observed arming again.
    func resetTriggers()
}
#endif
