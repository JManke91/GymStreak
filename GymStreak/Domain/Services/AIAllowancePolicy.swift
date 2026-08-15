//
//  AIAllowancePolicy.swift
//  GymStreak
//
//  P3/P4/P5 — the free monthly AI tasters, as pure logic over four scalars.
//  See docs/monetization-strategy.md §4.2a, §4.3, §7 and §8 D, and
//  docs/pro-subscription.md §5e.
//

import Foundation

/// Decides whether a metered AI surface still has free allowance left this
/// month, and whether the §8 placement D nudge belongs on screen.
///
/// Pure and isolation-agnostic like `RoutineCapPolicy` and `ChartGatingPolicy`:
/// it takes a consumed count, a limit and two flags and returns a decision. It
/// produces **no user-facing text** — each surface phrases its own allowance and
/// `Domain/` holds no localization keys.
///
/// The counting unit is deliberately *not* named here: for the chat it is a sent
/// message, for the recap and deep-dive a fresh generation. What they share is
/// this arithmetic, which is why one policy serves all three.
enum AIAllowancePolicy {

    /// What the nudge should say, without saying it.
    ///
    /// It carries `consumed` and `limit` rather than "remaining" because the
    /// meter in `OnyxCapNudge` draws the consumed proportion — the endowed
    /// progress effect §8 D is built on.
    enum NudgeState: Equatable {
        /// Exactly one unit left — §8 D's "1 of 5 remaining" hint.
        case lastRemaining(consumed: Int, limit: Int)
        /// Nothing left this month. The next attempt raises the paywall.
        case exhausted(consumed: Int, limit: Int)
    }

    /// `true` when the allowance applies to this user at all. A Founder is Pro,
    /// so this is `false` for them; with gating off it is `false` for everyone,
    /// which is what makes the shipped app behave exactly as it did before
    /// monetization.
    static func isMetered(isPro: Bool, isGatingEnabled: Bool) -> Bool {
        isGatingEnabled && !isPro
    }

    /// Units still available this month, clamped at zero. Meaningless for an
    /// unmetered user — ask `isMetered` first.
    static func remaining(consumed: Int, limit: Int) -> Int {
        max(0, limit - max(0, consumed))
    }

    /// `true` when the next generation must raise the paywall instead of
    /// running. Always `false` for a Pro user and with gating off.
    static func isExhausted(
        consumed: Int,
        limit: Int,
        isPro: Bool,
        isGatingEnabled: Bool
    ) -> Bool {
        guard isMetered(isPro: isPro, isGatingEnabled: isGatingEnabled) else { return false }
        return remaining(consumed: consumed, limit: limit) == 0
    }

    /// The nudge state, or `nil` when no hint belongs on screen.
    ///
    /// It starts on the **last free unit** and *stays* once the allowance is
    /// spent, for the same reason the routine cap nudge does: §8 D exists to
    /// remove the surprise from the gate that follows, and a hint that
    /// disappears exactly when the wall arrives would do the opposite.
    static func nudgeState(
        consumed: Int,
        limit: Int,
        isPro: Bool,
        isGatingEnabled: Bool
    ) -> NudgeState? {
        guard isMetered(isPro: isPro, isGatingEnabled: isGatingEnabled) else { return nil }
        let left = remaining(consumed: consumed, limit: limit)
        guard left <= 1 else { return nil }
        // Clamped, so a limit retuned *downwards* between releases cannot draw a
        // meter past full or print "6 of 5 used".
        let used = min(max(0, consumed), limit)
        return left == 0
            ? .exhausted(consumed: used, limit: limit)
            : .lastRemaining(consumed: used, limit: limit)
    }
}
