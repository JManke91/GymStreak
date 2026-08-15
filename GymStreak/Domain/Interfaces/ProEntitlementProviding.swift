//
//  ProEntitlementProviding.swift
//  GymStreak
//
//  The one abstraction every Pro gate asks "is this user Pro?" through. It has
//  no idea how the answer is produced. See docs/pro-subscription.md.
//

import Foundation

/// Reports the current Pro entitlement and its source.
///
/// Modelled on `AICoachAvailabilityProviding` — an observable state property
/// plus an async `refresh()` — because that is this codebase's established
/// shape for exposing a system-provided capability to ViewModels, and keeping
/// the two consistent means a gate reads like an availability check.
///
/// `@MainActor`: conformers hold mutable state read directly by SwiftUI, and
/// every consumer is a `@MainActor` ViewModel or View. Imports nothing beyond
/// Foundation on purpose — no conformer's purchase infrastructure (StoreKit,
/// RevenueCat) may ever appear in this signature.
@MainActor
protocol ProEntitlementProviding: AnyObject {

    /// The current entitlement, including where it comes from.
    var state: ProEntitlementState { get }

    /// Convenience: `true` whenever `state` grants Pro.
    var isPro: Bool { get }

    /// Re-resolves the entitlement from its underlying sources.
    func refresh() async
}

#if DEBUG
/// Debug-only entitlement surface behind the Settings debug sections.
///
/// Separate from `ProEntitlementProviding` so the release build's protocol
/// surface stays read-only: nothing in a shipping binary can write an
/// entitlement or start a purchase.
///
/// It carries both halves of the debug story because they are one question —
/// *what is this build reporting as Pro, and why* — and splitting them would
/// mean two protocols and two composition-root properties over the same object.
/// The store half is what makes a real Test Store purchase reachable before the
/// paywall exists (ticket 14); ticket 13 promotes restore to a shipping surface.
@MainActor
protocol ProEntitlementDebugging: ProEntitlementProviding {

    /// When non-`nil`, `state` reports this instead of the resolved entitlement.
    var simulatedState: ProEntitlementState? { get set }

    /// The entitlement as actually resolved, ignoring any override — so the
    /// picker can show *what it is overriding* rather than only its own value.
    var resolvedState: ProEntitlementState { get }

    /// The buyable products, or `[]` when none could be fetched.
    func availableProducts() async -> [ProPurchaseOption]

    func purchase(_ option: ProPurchaseOption) async -> ProPurchaseResult

    func restorePurchases() async
}
#endif
