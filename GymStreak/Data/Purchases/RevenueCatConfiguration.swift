//
//  RevenueCatConfiguration.swift
//  GymStreak
//
//  Every RevenueCat identifier the app depends on, in one place, so ticket 15's
//  Test Store → App Store swap is a one-line diff.
//  See docs/pro-subscription.md §3b.
//

import Foundation

/// The RevenueCat dashboard configuration the app is compiled against.
///
/// **These keys are not secrets.** RevenueCat's *public SDK* keys are designed
/// to ship inside the app binary — the repo's env-var-placeholder policy covers
/// `.mcp.json` server credentials, not this. A RevenueCat **secret** API key (the
/// REST one) must never appear in the app.
enum RevenueCatConfiguration {

    /// Test Store key. The `test_` prefix routes the SDK to RevenueCat's
    /// Simulated Store: offerings, purchases, entitlements and restore all work
    /// in the simulator with no App Store Connect products, which is what lets
    /// the purchase flow ship before Apple approves the real subscriptions.
    ///
    /// ⚠️ **No App Store submission may carry this key.** The SDK says so itself
    /// at launch: "Apps submitted with a Test Store API key will be rejected
    /// during App Review." Ticket 15 swaps `apiKey` to `appStoreAPIKey`, and
    /// that swap is a release blocker, not a cleanup.
    static let testStoreAPIKey = "test_IjLklyuZDXOVrXMjaURxfwJnWxk"

    /// The Apple production key (`appl_` prefix). Ticket 15 fills this in and
    /// points `apiKey` at it — that swap is the whole reason both keys live here.
    static let appStoreAPIKey = ""

    /// The key the app actually configures with.
    static let apiKey = testStoreAPIKey

    /// **Confirmed in the RevenueCat dashboard on 2026-08-15** (Product catalog →
    /// Entitlements → Gym Streak Pro, REST id `entl4a899fb281`): the identifier
    /// *is* the display name, spaces and capitals included.
    ///
    /// This is the single highest-risk string in the integration. A wrong value
    /// does not error — `entitlements[…]` simply returns `nil`, every paying user
    /// silently reads as free tier, and neither a build nor a test that stubs the
    /// gateway can catch it. It is only ever verified by a real Test Store
    /// purchase flipping the entitlement.
    static let proEntitlementIdentifier = "Gym Streak Pro"

    /// The three Test Store product identifiers attached to that entitlement.
    /// Only used as a fallback when no Offering is configured — the paywall
    /// (ticket 14) reads packages from the current Offering instead.
    /// App Store Connect product IDs will differ; mapping them is dashboard
    /// configuration, not code.
    static let proProductIdentifiers = ["lifetime", "yearly", "monthly"]
}
