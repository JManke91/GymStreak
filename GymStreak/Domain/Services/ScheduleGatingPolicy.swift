//
//  ScheduleGatingPolicy.swift
//  GymStreak
//
//  P9 — the free-tier planning gate, as pure logic over a schedule type and
//  two flags. See docs/monetization-strategy.md §4.2a P9 and §7, and
//  docs/pro-subscription.md §5f.
//

import Foundation

/// Decides whether a user may put a routine on a **fixed-weekday** plan.
///
/// Pure and isolation-agnostic like every other `Domain/Services` type, and it
/// produces no user-facing text — the lock copy comes from
/// `PaywallPlacement.headlineKey`, and `Domain/` holds no localization keys.
///
/// **What this deliberately does not decide.** Whether an *existing* schedule
/// keeps working. `WorkoutPlanningService` computes occurrences for whatever
/// schedule it is handed and never consults this type, which is what makes §7's
/// Rule 4 guarantee — a plan the user already built keeps driving the planned
/// week, the weekly goal and the up-next ordering forever — structurally true
/// rather than dependent on a check somebody might forget to write. This gate is
/// asked one question, at one moment: *may this user save a plan in this shape?*
enum ScheduleGatingPolicy {

    /// `true` when the planning gate applies to this user at all. A Founder is
    /// Pro, so this is `false` for them; with gating off it is `false` for
    /// everyone, which is what makes the shipped planner behave exactly as it
    /// did before monetization.
    static func isSubjectToGate(isPro: Bool, isGatingEnabled: Bool) -> Bool {
        isGatingEnabled && !isPro
    }

    /// `true` when saving a plan in this shape is Pro-only for this user.
    ///
    /// The rolling `.everyNDays` cadence is free, always — §4.2a gates the fixed
    /// weekly split and nothing else about planning. Passing the *requested*
    /// type (not the stored one) is what makes every route into weekday shape —
    /// creating one, switching an interval plan into one, editing an existing
    /// one's days — the same single check.
    static func isScheduleTypeLocked(
        _ type: RoutineScheduleType,
        isPro: Bool,
        isGatingEnabled: Bool
    ) -> Bool {
        isSubjectToGate(isPro: isPro, isGatingEnabled: isGatingEnabled) && type == .weekdays
    }
}
