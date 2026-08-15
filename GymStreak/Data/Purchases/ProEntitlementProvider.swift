//
//  ProEntitlementProvider.swift
//  GymStreak
//
//  The app's entitlement truth source: the Founder grant composed with the
//  purchased entitlement. See docs/pro-subscription.md.
//

import Foundation
import Observation

/// Composes the two things that can make a user Pro — the local Founder grant
/// and an active purchase — into the single `ProEntitlementState` every gate
/// reads.
///
/// `@Observable` + `@MainActor` like `AICoachAvailability`: `state` is mutable
/// state read directly by SwiftUI, so a purchase, a lapse, a restore or a
/// resolved Founder grant re-evaluates every gate with no app restart.
@Observable
@MainActor
final class ProEntitlementProvider: ProEntitlementProviding {

    /// The entitlement as actually resolved, ignoring any debug override.
    private(set) var resolvedState: ProEntitlementState

    private let founderStatus: any FounderStatusResolving
    private let purchases: any ProPurchaseGateway

    /// What the purchase layer last reported. Held separately from
    /// `resolvedState` so the two sources can be re-composed independently —
    /// which is what lets the Founder grant stand while RevenueCat is silent.
    private var purchased: PurchasedProEntitlement = .none

    /// The long-lived `entitlementUpdates()` iteration. Owned rather than
    /// detached: it must not outlive the provider.
    private var purchaseObservation: Task<Void, Never>?

    #if DEBUG
    var simulatedState: ProEntitlementState?
    #endif

    /// - Parameters:
    ///   - founderStatus: deliberately has no default. A default would be the
    ///     real `UserDefaults.standard`-and-StoreKit-backed service, and a test
    ///     that constructed this provider without noticing would reach for
    ///     `AppTransaction` from the test process.
    ///   - purchases: the purchase layer, for the same reason — a default would
    ///     configure and call RevenueCat from a test.
    init(
        resolvedState: ProEntitlementState = .free,
        founderStatus: any FounderStatusResolving,
        purchases: any ProPurchaseGateway
    ) {
        self.resolvedState = resolvedState
        self.founderStatus = founderStatus
        self.purchases = purchases

        let updates = purchases.entitlementUpdates()
        purchaseObservation = Task { [weak self] in
            for await entitlement in updates {
                guard let self else { return }
                self.purchased = entitlement
                self.recompose()
            }
        }
    }

    /// `isolated deinit` (SE-0371): the observation task is main-actor state and
    /// a plain `deinit` is `nonisolated`, so it could not read it. Without the
    /// cancellation the relay would keep iterating `customerInfoStream` after
    /// the provider is gone.
    isolated deinit {
        purchaseObservation?.cancel()
    }

    var state: ProEntitlementState {
        #if DEBUG
        simulatedState ?? resolvedState
        #else
        resolvedState
        #endif
    }

    var isPro: Bool { state.isPro }

    /// Resolves the Founder grant (at most once per install) and re-reads the
    /// purchased entitlement.
    ///
    /// Composed **twice**, on purpose: a granted Founder is live before the
    /// network call is even attempted, so a user who was here first keeps Pro
    /// when RevenueCat is unreachable, slow, or never answers at all.
    func refresh() async {
        await founderStatus.resolveIfNeeded()
        recompose()
        purchased = await purchases.currentEntitlement()
        recompose()
    }

    /// Founder wins. The grant is local, permanent and offline-durable, so it
    /// takes precedence over anything the network says — including "no
    /// purchase", which is also what a failed lookup reports.
    ///
    /// The consequence, accepted knowingly: a Founder who somehow *also* holds a
    /// subscription reads as `.founder`, so Settings (ticket 13) would show the
    /// grandfathered source rather than the paid one. A Founder is never shown a
    /// paywall, so nothing in the app can produce that pairing.
    private func recompose() {
        guard !founderStatus.isFounder else {
            resolvedState = .founder
            return
        }
        switch purchased {
        case .none: resolvedState = .free
        case .subscription: resolvedState = .subscription
        case .lifetime: resolvedState = .lifetime
        }
    }
}

#if DEBUG
/// The debug entitlement surface. Both halves — simulating a state and driving
/// the real store — are DEBUG-only, so a shipping binary has no writable
/// entitlement and no purchase entry point at all until ticket 14's paywall.
extension ProEntitlementProvider: ProEntitlementDebugging {

    func availableProducts() async -> [ProPurchaseOption] {
        await purchases.availableProducts()
    }

    func purchase(_ option: ProPurchaseOption) async -> ProPurchaseResult {
        let result = await purchases.purchase(option)
        if result == .purchased {
            // The stream reports this too; reading it back makes the entitlement
            // observable the instant the sheet dismisses rather than a round-trip
            // later.
            purchased = await purchases.currentEntitlement()
            recompose()
        }
        return result
    }

    func restorePurchases() async {
        purchased = await purchases.restorePurchases()
        recompose()
    }
}
#endif
