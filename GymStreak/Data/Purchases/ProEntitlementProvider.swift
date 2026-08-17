//
//  ProEntitlementProvider.swift
//  GymStreak
//
//  The app's entitlement truth source: the Founder grant composed with the
//  purchased entitlement. See docs/pro-subscription.md.
//

import Foundation
import Observation
import OSLog

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

    /// Re-reads the purchased entitlement and resolves the Founder grant.
    ///
    /// Composed **three** times, and the order is the fix for a bug rather than
    /// a preference (docs/pro-subscription.md §3d):
    ///
    /// 1. Immediately, before any I/O — a Founder grant already on record is
    ///    live without waiting for anything.
    /// 2. After the purchase read. This one used to run *last*, queued behind
    ///    `resolveIfNeeded()`, and that is what broke the purchase flow: the
    ///    Founder resolution round-trips StoreKit's `AppTransaction`, and in
    ///    every non-production environment it can never record a decision, so it
    ///    re-attempts that round-trip on every single call. A refresh fired the
    ///    moment a user paid therefore sat behind a StoreKit call that can take
    ///    tens of seconds — or, mid-purchase, block on an App Store sign-in
    ///    prompt that never appears — and the entitlement it was supposed to
    ///    deliver never arrived.
    /// 3. After the Founder resolution, for a grant that resolved just now.
    ///
    /// A read that *failed* writes nothing at all. `.none` from this method used
    /// to mean both "no purchase" and "could not ask", so an offline refresh
    /// revoked an entitlement the stream had already delivered.
    func refresh() async {
        recompose()

        do {
            purchased = try await purchases.currentEntitlement()
            recompose()
        } catch {
            // Offline, or the backend failed. Never "revoked": whatever the
            // stream last delivered stands, and the next emission corrects it.
            Self.logger.info(
                """
                Entitlement read failed, keeping \
                \(String(describing: self.purchased), privacy: .public) — \
                \(String(describing: error), privacy: .public)
                """
            )
        }

        await founderStatus.resolveIfNeeded()
        recompose()
    }

    /// Founder wins. The grant is local, permanent and offline-durable, so it
    /// takes precedence over anything the network says — including "no
    /// purchase". (A *failed* lookup no longer says anything at all: since §3d
    /// the two reads throw rather than reporting `.none`.)
    ///
    /// The consequence, accepted knowingly: a Founder who somehow *also* holds a
    /// subscription reads as `.founder`, so Settings (ticket 13) would show the
    /// grandfathered source rather than the paid one. A Founder is never shown a
    /// paywall, so nothing in the app can produce that pairing.
    private func recompose() {
        let composed: ProEntitlementState
        if founderStatus.isFounder {
            composed = .founder
        } else {
            switch purchased {
            case .none: composed = .free
            case .subscription: composed = .subscription
            case .lifetime: composed = .lifetime
            }
        }
        // For the log line, and as belt and braces under it. `refresh()`
        // recomposes three times per call and has three callers, so most
        // recompositions write the value that is already there; an unconditional
        // log would bury the one transition worth reading. Observation happens to
        // suppress the redundant *notification* on its own — the `@Observable`
        // macro compares `Equatable` values before notifying, and
        // `ProEntitlementState` is a raw-value enum (`idempotentStateDoesNotNotify`
        // pins that) — but that guarantee lives in the property's conformance,
        // not here, and this guard is what makes it not matter.
        guard composed != resolvedState else { return }
        Self.logger.info(
            """
            Entitlement \(self.resolvedState.rawValue, privacy: .public) → \
            \(composed.rawValue, privacy: .public)
            """
        )
        resolvedState = composed
    }

    private static let logger = Logger(subsystem: "app.gymstreak.pro", category: "Entitlement")
}

#if DEBUG
/// The debug entitlement surface. Both halves — simulating a state and driving
/// the real store — are DEBUG-only, so a shipping binary has no writable
/// entitlement and no purchase entry point at all until ticket 14's paywall.
extension ProEntitlementProvider: ProEntitlementDebugging {

    /// The two backend facts, projected from the Data layer's configuration so
    /// the debug section never has to name it (§9.4a).
    var storeBackendDescription: String { RevenueCatConfiguration.backendDescription }

    var isUsingTestStore: Bool { RevenueCatConfiguration.isUsingTestStore }

    func availableProducts() async -> [ProPurchaseOption] {
        await purchases.availableProducts()
    }

    func purchase(_ option: ProPurchaseOption) async -> ProPurchaseResult {
        let result = await purchases.purchase(option)
        if result == .purchased {
            // The stream reports this too; reading it back makes the entitlement
            // observable the instant the sheet dismisses rather than a round-trip
            // later.
            if let entitlement = try? await purchases.currentEntitlement() {
                purchased = entitlement
                recompose()
            }
        }
        return result
    }

    func restorePurchases() async {
        // A restore that could not run found nothing to *report*, which is not
        // the same as finding nothing — and must not revoke what is already held.
        guard let entitlement = try? await purchases.restorePurchases() else { return }
        purchased = entitlement
        recompose()
    }
}
#endif
