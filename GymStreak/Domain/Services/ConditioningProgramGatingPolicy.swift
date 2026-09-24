//
//  ConditioningProgramGatingPolicy.swift
//  GymStreak
//
//  P12 — the free-tier depth gate on the 12-week conditioning program, as pure
//  logic over a week number and two flags. See docs/monetization-strategy.md
//  §4.2a P12 and §3 Rule 2, docs/pro-subscription.md §5l and
//  docs/fight-conditioning.md.
//

import Foundation

/// Decides how deep into the 12-week fight-conditioning program a user may go.
///
/// Pure and isolation-agnostic like every other `Domain/Services` type, and it
/// produces **no user-facing text** — the lock copy comes from
/// `PaywallPlacement.headlineKey`, and `Domain/` holds no localization keys.
///
/// **The gate fires after investment, never before it** (§3 Rule 2). Phase 1 —
/// four weeks of aerobic base — is free in full, so a free user has trained the
/// program for a month before anything locks, and what locks is the continuation
/// of *their own* plan rather than a feature they have never seen.
///
/// **What this deliberately does not decide.** Whether a session can be run.
/// Nothing in the runner, the watch offer's own logic, the history or the single
/// session library asks this type anything — §3 Rules 3 and 4 make those
/// permanently free, and the way to keep that true is for the gate to have no
/// reach into them. The one question asked here is: *may this user be shown, and
/// handed, the plan for this program week?* A locked week withholds the week's
/// prescription; it never touches a logged session, and it never deletes or
/// rewinds the enrollment — a lapsed subscriber resumes exactly where they were
/// the moment they resubscribe.
enum ConditioningProgramGatingPolicy {

    /// `true` when the program depth gate applies to this user at all. A Founder
    /// is Pro, so this is `false` for them; with gating off it is `false` for
    /// everyone, which is what makes the shipped program behave exactly as it
    /// did before ticket 08.
    static func isSubjectToGate(isPro: Bool, isGatingEnabled: Bool) -> Bool {
        isGatingEnabled && !isPro
    }

    /// `true` when this program week is Pro-only for this user.
    ///
    /// The free depth comes from `ProFeatureCaps`, never from a literal here:
    /// §4.4's argument that every free-tier number must be retunable in a
    /// one-line diff applies to this one too.
    static func isWeekLocked(
        _ week: Int,
        isPro: Bool,
        isGatingEnabled: Bool,
        freeWeeks: Int = ProFeatureCaps.freeConditioningProgramWeeks
    ) -> Bool {
        isSubjectToGate(isPro: isPro, isGatingEnabled: isGatingEnabled) && week > freeWeeks
    }

    /// `true` when a whole phase lies beyond the free depth — the phase is
    /// locked only if its *first* week is, so the phase that straddles the
    /// boundary (none, at the shipped cap of 4) would stay open.
    static func isPhaseLocked(
        _ phase: ConditioningProgramPhase,
        isPro: Bool,
        isGatingEnabled: Bool,
        freeWeeks: Int = ProFeatureCaps.freeConditioningProgramWeeks
    ) -> Bool {
        isWeekLocked(phase.weeks.lowerBound, isPro: isPro, isGatingEnabled: isGatingEnabled, freeWeeks: freeWeeks)
    }

    /// `true` in the last week a gated user gets for free — §8 placement D's
    /// cue to say "Phase 2 starts next week" *before* the wall rather than at
    /// it. Never `true` for a user the gate does not apply to: a Founder told
    /// their program is about to end is the §7 scenario the grant exists to
    /// prevent.
    static func isLastFreeWeek(
        _ week: Int,
        isPro: Bool,
        isGatingEnabled: Bool,
        freeWeeks: Int = ProFeatureCaps.freeConditioningProgramWeeks
    ) -> Bool {
        isSubjectToGate(isPro: isPro, isGatingEnabled: isGatingEnabled) && week == freeWeeks
    }
}
