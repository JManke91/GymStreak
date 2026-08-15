//
//  RoutineCapPolicy.swift
//  GymStreak
//
//  P1 — the free-tier routine cap, as pure logic over three scalars.
//  See docs/monetization-strategy.md §4.2a, §4.4 and §7, and
//  docs/pro-subscription.md §5c.
//

import Foundation

/// Decides whether the free-tier routine cap applies, and whether the §8
/// placement D nudge belongs on screen.
///
/// Pure and isolation-agnostic like every other `Domain/Services` type: it takes
/// a count and two flags and returns a decision. It deliberately produces **no
/// user-facing text** — the copy each state needs is a Presentation concern, and
/// `Domain/` has no business holding localization keys.
///
/// The counting unit is a **saved routine template**. Starting a workout from a
/// routine is unlimited, always, so nothing on the workout path ever calls this.
enum RoutineCapPolicy {

    /// What the nudge should say, without saying it. `used` is the raw routine
    /// count, so a lapsed Pro user legitimately reports more than `limit`.
    enum NudgeState: Equatable {
        /// The last free slot — "2 of 3 routines used".
        case approaching(used: Int, limit: Int)
        /// At or above the cap. Carries no numbers to phrase, because a user
        /// who lapsed from Pro can be at 6 of 3 and "all 3 used" would be false.
        case reached(used: Int, limit: Int)
    }

    /// `true` when the cap applies to this user at all. A Founder is Pro, so
    /// this is `false` for them; with gating off it is `false` for everyone,
    /// which is what makes the shipped app behave exactly as it did before
    /// monetization.
    static func isSubjectToCap(isPro: Bool, isGatingEnabled: Bool) -> Bool {
        isGatingEnabled && !isPro
    }

    /// `true` when saving another routine template would go past the cap — and
    /// therefore also for a lapsed user already above it. Per §7's Rule 4 they
    /// keep every routine they made; only *creating another* is refused.
    static func isCapReached(
        routineCount: Int,
        isPro: Bool,
        isGatingEnabled: Bool,
        limit: Int = ProFeatureCaps.freeRoutineLimit
    ) -> Bool {
        isSubjectToCap(isPro: isPro, isGatingEnabled: isGatingEnabled) && routineCount >= limit
    }

    /// The nudge state, or `nil` when no hint belongs on screen.
    ///
    /// It starts on the **last free slot** and *stays* once the cap is reached:
    /// §8 D's whole purpose is to remove the surprise from the gate that
    /// follows, and a hint that disappears exactly when the wall arrives would
    /// do the opposite.
    static func nudgeState(
        routineCount: Int,
        isPro: Bool,
        isGatingEnabled: Bool,
        limit: Int = ProFeatureCaps.freeRoutineLimit
    ) -> NudgeState? {
        guard isSubjectToCap(isPro: isPro, isGatingEnabled: isGatingEnabled) else { return nil }
        guard routineCount >= limit - 1 else { return nil }
        return routineCount >= limit
            ? .reached(used: routineCount, limit: limit)
            : .approaching(used: routineCount, limit: limit)
    }
}
