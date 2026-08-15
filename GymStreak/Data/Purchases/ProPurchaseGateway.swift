//
//  ProPurchaseGateway.swift
//  GymStreak
//
//  The seam between the entitlement provider and RevenueCat, so the composition
//  of "Founder grant + purchased entitlement" is unit-testable without a store.
//  See docs/pro-subscription.md §3b.
//

import Foundation

/// The Pro entitlement as the *purchase layer* reports it.
///
/// Deliberately not `ProEntitlementState`: a purchase gateway can never produce
/// `.founder`, and a type that can express it would make the composition in
/// `ProEntitlementProvider` look total when it is not.
enum PurchasedProEntitlement: Equatable, Sendable {

    /// No active purchase — including "we could not ask". Never a decision the
    /// app persists, and never a reason to revoke the Founder grant.
    case none

    /// An active auto-renewing subscription (monthly or yearly).
    case subscription

    /// The non-expiring lifetime unlock.
    case lifetime
}

/// Reads and drives the purchase layer.
///
/// Exists for the same reason `OriginalAppDownloadReading` does: RevenueCat's
/// `Purchases` is a configured singleton whose `CustomerInfo` cannot be
/// constructed in a test, so without this seam none of the composition branches
/// — the ones that silently grant or withhold Pro — could be covered at all.
///
/// **No method throws.** Every failure here degrades to "no purchase seen": a
/// gate must never crash or hang because RevenueCat is unreachable, and the
/// Founder grant is resolved on a path that does not touch this protocol.
///
/// `@MainActor` to match `ProEntitlementProviding`; the SDK's async surface is
/// isolation-agnostic and `CustomerInfo` is `Sendable`, so awaiting it from the
/// main actor needs no escape hatch (Concurrency rule 5).
@MainActor
protocol ProPurchaseGateway: AnyObject {

    /// Emits the currently-known entitlement immediately, then every change.
    /// Long-lived: the caller owns the iteration and cancels it on teardown.
    func entitlementUpdates() -> AsyncStream<PurchasedProEntitlement>

    /// One-shot read, for the launch refresh.
    func currentEntitlement() async -> PurchasedProEntitlement

    /// The buyable products, or `[]` when none can be fetched (offline, or
    /// nothing configured) — an empty list is what keeps a purchase surface from
    /// presenting an empty sheet.
    func availableProducts() async -> [ProPurchaseOption]

    func purchase(_ option: ProPurchaseOption) async -> ProPurchaseResult

    /// Re-syncs purchases made on another device or before a reinstall.
    func restorePurchases() async -> PurchasedProEntitlement
}
