//
//  ProGating.swift
//  GymStreak
//
//  The single global switch that turns Pro gating on. Ships off.
//  See docs/monetization-strategy.md §9 and docs/pro-subscription.md.
//

import Foundation

/// Master switch for every Pro gate in the app.
///
/// One flag, not one per gate: §9's rollout ships the entitlement layer
/// silently (Phase 1) and flips gating on in a later release (Phase 2), so
/// every gate must be a no-op in the shipped app until that single flip. A
/// per-gate flag set would make "is gating live?" un-answerable at a glance and
/// allow a half-gated release.
///
/// A gate reads this *and* the entitlement — `ProGating.isEnabled` alone never
/// blocks anything, and with it `false` the app behaves exactly as it did
/// before monetization.
enum ProGating {

    /// `false` until the Phase 2 launch release (ticket 15) flips it.
    static let isEnabled: Bool = false
}
