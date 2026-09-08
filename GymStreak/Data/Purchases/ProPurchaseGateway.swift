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

    /// No active purchase — a fact about the *account*, and one that
    /// legitimately drops the entitlement. It emphatically does **not** cover
    /// "we could not ask": that is an error, because folding the two together is
    /// how an offline refresh came to revoke a live subscription (§3d). Never a
    /// decision the app persists, and never a reason to revoke the Founder grant.
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
/// **"Could not ask" is an error, not an answer.** The two reads throw rather
/// than reporting `.none`, because the caller has to tell them apart: `.none` is
/// a fact about the account that legitimately revokes Pro, while a failed lookup
/// is a fact about the network and must leave a live entitlement alone. Folding
/// the second into the first is what let an offline launch refresh silently
/// un-buy a subscription the stream had just delivered (docs/pro-subscription.md
/// §3d). Neither error is ever surfaced to a gate — the provider swallows both.
///
/// `@MainActor` to match `ProEntitlementProviding`; the SDK's async surface is
/// isolation-agnostic and `CustomerInfo` is `Sendable`, so awaiting it from the
/// main actor needs no escape hatch (Concurrency rule 5).
@MainActor
protocol ProPurchaseGateway: AnyObject {

    /// Emits the currently-known entitlement immediately, then every change.
    /// Long-lived: the caller owns the iteration and cancels it on teardown.
    func entitlementUpdates() -> AsyncStream<PurchasedProEntitlement>

    /// One-shot read, for the launch refresh and the post-purchase re-read.
    /// Throws when the purchase layer could not be reached at all.
    func currentEntitlement() async throws -> PurchasedProEntitlement

    /// The buyable products, or `[]` when none can be fetched (offline, or
    /// nothing configured) — an empty list is what keeps a purchase surface from
    /// presenting an empty sheet.
    func availableProducts() async -> [ProPurchaseOption]

    func purchase(_ option: ProPurchaseOption) async -> ProPurchaseResult

    /// Re-syncs purchases made on another device or before a reinstall.
    /// Throws for the same reason `currentEntitlement()` does: a restore that
    /// could not run is not a restore that found nothing.
    func restorePurchases() async throws -> PurchasedProEntitlement

    /// Tags this (anonymous) customer with the resolved Founder decision, so the
    /// purchase backend's charts can separate the never-chargeable
    /// grandfathered base from everyone else.
    ///
    /// **Analytics only, and one-way.** The grant itself is decided from
    /// `AppTransaction` and cached locally (`FounderStatusService`); nothing
    /// reads this back to decide an entitlement, because a grandfathered user
    /// must never depend on a network call to keep what they were promised
    /// (docs/monetization-strategy.md §9).
    ///
    /// **Neither `async` nor `throws`, deliberately.** A signature that could
    /// suspend or fail would put a reporting call on the path of the Founder
    /// grant and the composed `ProEntitlementState` — the two things a backend
    /// outage must not be able to touch. Implementations record the value
    /// locally and let the SDK sync it whenever it next talks to the backend.
    ///
    /// Called from every `refresh()` — so at launch, and again on paywall
    /// dismiss and after a Customer Center restore. Reporting is idempotent, so
    /// re-sending is both cheap and the recovery path for a first sync that
    /// never landed; there is deliberately no "have I already sent this" flag.
    ///
    /// A `Bool`, not a RevenueCat type: no SDK type crosses this seam in either
    /// direction, and `RevenueCatPurchaseGateway` stays the only place the
    /// entitlement and attribution surfaces are named (docs/pro-subscription.md
    /// §3b — the two `RevenueCatUI` paywall hosts of §5j are the one documented
    /// exception, and they touch neither surface).
    func reportFounderStatus(_ isFounder: Bool)
}
