//
//  RevenueCatPurchaseGateway.swift
//  GymStreak
//
//  The one and only file in the app that imports RevenueCat.
//  See docs/pro-subscription.md §3b.
//

import Foundation
import RevenueCat

/// Configures the RevenueCat SDK and projects `CustomerInfo` down to the two
/// facts the app decides on.
///
/// **Nothing above `Data/Purchases/` may import RevenueCat**, and this file is
/// where that line is drawn: no `CustomerInfo`, `Package`, `EntitlementInfo` or
/// `ErrorCode` appears in any signature outside it.
@MainActor
final class RevenueCatPurchaseGateway: ProPurchaseGateway {

    /// What `availableProducts()` last handed out, so `purchase(_:)` can resolve
    /// an option's identifier back to the store object without that object ever
    /// crossing the seam.
    private var purchasables: [String: Purchasable] = [:]

    private enum Purchasable {
        case package(Package)
        case product(StoreProduct)
    }

    /// Configures the SDK. Called from the composition root, which runs in
    /// `GymStreakApp.init()` — i.e. before any UI exists and before anything can
    /// read an entitlement.
    ///
    /// `appUserID: nil` makes the SDK generate and cache an anonymous identifier.
    /// That is what preserves the no-account promise (`monetization-strategy.md`
    /// §1): there is no login, and `collectDeviceIdentifiers()` is deliberately
    /// never called — it pulls in `AdSupport` for attribution this app does not do.
    init() {
        // Re-entrant by design: an app-hosted test run may build a second
        // composition root in the same process, and configuring twice trips the
        // SDK's own warning.
        guard !Purchases.isConfigured else { return }

        Purchases.logLevel = .warn

        Purchases.configure(
            with: Configuration.Builder(withAPIKey: RevenueCatConfiguration.apiKey)
                .with(appUserID: nil)
                // `.informational` never blocks access on its own — it only
                // *surfaces* the signal, which `entitlement(in:)` then acts on.
                .with(entitlementVerificationMode: .informational)
                .with(storeKitVersion: .storeKit2)
                .build()
        )
    }

    // MARK: - Reading

    /// Wraps `customerInfoStream`, which yields the cached `CustomerInfo`
    /// immediately on iteration and then every update — so a subscription bought
    /// on another device, a lapse, or a restore all land without an app restart.
    ///
    /// The relay `Task` is owned by the returned stream: cancelling the
    /// iteration (the provider's `isolated deinit`) terminates the continuation,
    /// which cancels the relay. No detached task outlives the caller.
    func entitlementUpdates() -> AsyncStream<PurchasedProEntitlement> {
        let customerInfoStream = Purchases.shared.customerInfoStream
        return AsyncStream { continuation in
            let relay = Task {
                for await customerInfo in customerInfoStream {
                    continuation.yield(Self.entitlement(in: customerInfo))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in relay.cancel() }
        }
    }

    func currentEntitlement() async -> PurchasedProEntitlement {
        do {
            return Self.entitlement(in: try await Purchases.shared.customerInfo())
        } catch {
            // Offline, or the backend failed. "Not seen" — never "revoked", and
            // never persisted: the Founder grant resolves on its own path and
            // the next stream emission corrects this.
            return .none
        }
    }

    /// Reduces a customer record to the app's entitlement.
    ///
    /// Two judgements live here:
    ///
    /// - **`.failed` verification never grants.** That case means the response
    ///   could not be authenticated (the MITM/forgery vector), so it fails closed,
    ///   consistent with the position `monetization-strategy.md` §7.1 takes on
    ///   unverified `AppTransaction`s. `.notRequested` and `.verifiedOnDevice` are
    ///   *not* failures and do grant.
    /// - **Lifetime is the non-expiring grant.** A subscription always carries an
    ///   `expirationDate`, even once cancelled but not yet lapsed; the one-time
    ///   purchase carries none. There is no `isLifetime` flag to read.
    ///
    /// `nonisolated` because it is pure and is called from the stream relay.
    nonisolated private static func entitlement(
        in customerInfo: CustomerInfo
    ) -> PurchasedProEntitlement {
        guard
            let pro = customerInfo.entitlements[RevenueCatConfiguration.proEntitlementIdentifier],
            pro.isActive,
            pro.verification != .failed
        else {
            return .none
        }
        return pro.expirationDate == nil ? .lifetime : .subscription
    }

    // MARK: - Buying

    /// The current Offering's packages, falling back to a direct product lookup.
    ///
    /// The Offering is the path the paywall (ticket 14) uses. The fallback exists
    /// because an entitlement can be fully configured with its products *before*
    /// anyone builds an Offering around them, and a purchase surface that shows
    /// nothing in that state is indistinguishable from a broken integration.
    /// Both paths return `[]` rather than throwing: no products means no purchase
    /// UI, not an error.
    func availableProducts() async -> [ProPurchaseOption] {
        purchasables = [:]

        if let packages = try? await Purchases.shared.offerings().current?.availablePackages,
           !packages.isEmpty {
            for package in packages {
                purchasables[package.identifier] = .package(package)
            }
            return packages.map {
                ProPurchaseOption(
                    id: $0.identifier,
                    displayName: $0.storeProduct.localizedTitle,
                    price: $0.storeProduct.localizedPriceString
                )
            }
        }

        let products = await Purchases.shared.products(
            RevenueCatConfiguration.proProductIdentifiers
        )
        for product in products {
            purchasables[product.productIdentifier] = .product(product)
        }
        return products.map {
            ProPurchaseOption(
                id: $0.productIdentifier,
                displayName: $0.localizedTitle,
                price: $0.localizedPriceString
            )
        }
    }

    /// Buys an option previously handed out by `availableProducts()`.
    ///
    /// Cancellation arrives on **two** paths and neither is an error: the async
    /// API returns normally with `userCancelled == true`, while some code paths
    /// still throw `ErrorCode.purchaseCancelledError`. Both map to `.cancelled`.
    func purchase(_ option: ProPurchaseOption) async -> ProPurchaseResult {
        guard let purchasable = purchasables[option.id] else {
            return .failed("No store product for \(option.id).")
        }
        do {
            let result: PurchaseResultData
            switch purchasable {
            case .package(let package):
                result = try await Purchases.shared.purchase(package: package)
            case .product(let product):
                result = try await Purchases.shared.purchase(product: product)
            }
            return result.userCancelled ? .cancelled : .purchased
        } catch ErrorCode.purchaseCancelledError {
            return .cancelled
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func restorePurchases() async -> PurchasedProEntitlement {
        do {
            return Self.entitlement(in: try await Purchases.shared.restorePurchases())
        } catch {
            return .none
        }
    }
}
