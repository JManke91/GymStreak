//
//  ProEntitlementState.swift
//  GymStreak
//
//  The app's answer to "is this user Pro, and why" — the truth source every
//  future gate reads. See docs/pro-subscription.md.
//

import Foundation

/// Whether the current user has Pro, and *where* that entitlement comes from.
///
/// The case **is** the source: the reason a user is Pro is never redundant with
/// the fact that they are, because the Founder screen (ticket 12) and the
/// subscription section in Settings (ticket 13) have to distinguish "Pro because
/// you paid" from "Pro because you were here first". Modelling this as a plain
/// `Bool` would mean retrofitting the source onto every call site later.
///
/// Deliberately free of any purchase-infrastructure vocabulary — nothing here
/// names StoreKit or RevenueCat, so the Data-layer implementation can be
/// swapped (ticket 03) without touching a single consumer.
enum ProEntitlementState: String, CaseIterable, Sendable {

    /// Free tier — the complete workout tracker, no Pro capacity or depth.
    ///
    /// Named `free`, not `none`, on purpose: as `ProEntitlementState?` — which
    /// is exactly how the debug override stores it — a written `.none` would
    /// silently resolve to `Optional.none` (i.e. "no override") instead of the
    /// free tier.
    case free

    /// Grandfathered: installed before the monetization cutoff build (§7).
    /// Permanent, local, and resolved without a network round-trip.
    case founder

    /// An active auto-renewing subscription (monthly or yearly).
    case subscription

    /// The one-time lifetime purchase.
    case lifetime

    /// `true` for every source that grants Pro.
    var isPro: Bool { self != .free }
}
