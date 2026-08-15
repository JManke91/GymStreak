//
//  MonthlyAllowanceTracking.swift
//  GymStreak
//
//  How a gate asks "how much of this month's free allowance is spent?" without
//  knowing where the count lives. See docs/pro-subscription.md §5e.
//

import Foundation

/// The month-keyed consumption counters behind the free AI tasters (P3/P4/P5).
///
/// Three verbs, because the taster semantics are exactly three decisions
/// (docs/monetization-strategy.md §4.2a, and §5e of the subscription doc):
/// consumption happens on a **successful start**, a **failure gives the unit
/// back**, and everything else — opening a screen, re-reading history — asks
/// nothing of this protocol at all.
///
/// `@MainActor` like the rest of the Pro protocol surface: the counts are read
/// during a ViewModel's `body`-facing computation, so a conformer must be able
/// to answer synchronously from memory. Imports nothing beyond Foundation on
/// purpose — no `UserDefaults` suite name and no `NSUbiquitousKeyValueStore`
/// may appear in this signature.
@MainActor
protocol MonthlyAllowanceTracking: AnyObject {

    /// Units consumed on `surface` in the **current** calendar month. `0` once
    /// the month rolls over.
    ///
    /// Cheap by contract — a gate calls this from a computed property that a
    /// view body reads, so a conformer answers from memory, never from I/O.
    func consumedCount(for surface: MeteredAISurface) -> Int

    /// Records one consumed unit against the current month.
    func consume(_ surface: MeteredAISurface)

    /// Gives one unit back — a generation that failed, or one that never
    /// started. Never goes below zero.
    func refund(_ surface: MeteredAISurface)
}
