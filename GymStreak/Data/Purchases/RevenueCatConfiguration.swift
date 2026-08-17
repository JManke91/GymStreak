//
//  RevenueCatConfiguration.swift
//  GymStreak
//
//  Every RevenueCat identifier the app depends on, in one place.
//  See docs/pro-subscription.md §3b and §9.4a.
//

import Foundation

/// The RevenueCat dashboard configuration the app is compiled against.
///
/// **These keys are not secrets.** RevenueCat's *public SDK* keys are designed
/// to ship inside the app binary — the repo's env-var-placeholder policy covers
/// `.mcp.json` server credentials, not this. A RevenueCat **secret** API key (the
/// REST one) must never appear in the app.
enum RevenueCatConfiguration {

    /// The Apple production key (`appl_` prefix) for the live RevenueCat
    /// project. It is what a Release build configures with, and what a Debug
    /// build launched with `appStoreBackendLaunchArgument` configures with.
    ///
    /// "Production key" names the *project*, not the purchase environment: the
    /// same key serves sandbox and production, and the SDK routes to whichever
    /// the build's receipt says it is in. This is the key that must be live for
    /// a real sandbox purchase on a device to reach RevenueCat at all.
    static let appStoreAPIKey = "appl_NjUvNeWpHECDnqaxDNJcFnbAhoW"

    /// **Confirmed in the RevenueCat dashboard on 2026-08-15** (Product catalog →
    /// Entitlements → Gym Streak Pro, REST id `entl4a899fb281`): the identifier
    /// *is* the display name, spaces and capitals included.
    ///
    /// This is the single highest-risk string in the integration. A wrong value
    /// does not error — `entitlements[…]` simply returns `nil`, every paying user
    /// silently reads as free tier, and neither a build nor a test that stubs the
    /// gateway can catch it. It is only ever verified by a real purchase flipping
    /// the entitlement — against the Test Store, and again against the sandbox,
    /// because the two are different backends.
    static let proEntitlementIdentifier = "Gym Streak Pro"

    /// The product identifiers to fall back on when no Offering is configured.
    /// The paywall reads packages from the Offering instead (§5j); this list is
    /// only used by the debug store section, and it has to follow the backend —
    /// the Test Store's products are not the App Store's.
    static var proProductIdentifiers: [String] {
        #if DEBUG
        return isUsingTestStore ? testStoreProductIdentifiers : appStoreProductIdentifiers
        #else
        return appStoreProductIdentifiers
        #endif
    }

    /// The App Store Connect products. Both subscriptions were in App Review on
    /// 2026-08-16 — which does **not** stop them being bought in the sandbox
    /// (§9.4a). There is no Lifetime identifier here yet: §6's one-time SKU is a
    /// **non-consumable**, and Apple counts that as its own product type whose
    /// first instance must be submitted with an app version of its own.
    static let appStoreProductIdentifiers = [
        "gymstreak.iap.pro.yearly.sub",
        "gymstreak.iap.pro.monthly.sub"
    ]

    // MARK: - Which backend this build talks to

    #if DEBUG

    /// Test Store key. The `test_` prefix routes the SDK to RevenueCat's
    /// Simulated Store: offerings, purchases, entitlements and restore all work
    /// in the simulator with no App Store Connect products and no sandbox
    /// account, which is what makes the purchase path exercisable where the real
    /// sandbox cannot be reached (§9.4).
    ///
    /// ⚠️ **No App Store submission may carry this key.** The SDK says so itself
    /// at launch: "Apps submitted with a Test Store API key will be rejected
    /// during App Review." Hence `#if DEBUG` around the literal itself and not
    /// merely around its use: a Release binary does not contain the string at
    /// all, so §9.6's `strings` check on the shipped binary is a real check
    /// rather than one that can never pass.
    static let testStoreAPIKey = "test_IjLklyuZDXOVrXMjaURxfwJnWxk"

    /// The Simulated Store's products, created in the RevenueCat dashboard.
    static let testStoreProductIdentifiers = ["lifetime", "yearly", "monthly"]

    /// Add to the scheme under Run → Arguments → Arguments Passed On Launch to
    /// point a Debug build at the real App Store backend — which is the
    /// prerequisite for testing against the sandbox on a device (§9.4a).
    static let appStoreBackendLaunchArgument = "-REVENUECAT_APP_STORE"

    static var isAppStoreBackendForced: Bool {
        ProcessInfo.processInfo.arguments.contains(appStoreBackendLaunchArgument)
    }

    /// A Debug build defaults to the Test Store, because that is the one backend
    /// reachable from the simulator, where most development happens.
    static let apiKey: String = isAppStoreBackendForced ? appStoreAPIKey : testStoreAPIKey

    /// Whether this run talks to the Simulated Store rather than to Apple.
    /// Derived from the key actually in use, so it cannot drift from it.
    static var isUsingTestStore: Bool { apiKey == testStoreAPIKey }

    /// What the debug sections print, so "no products" is diagnosable: the same
    /// empty list means a wrong key, an inactive Paid Applications Agreement, a
    /// product not configured, or the simulator (§9.4a's failure table).
    static var backendDescription: String {
        isUsingTestStore ? "Test Store (simulated)" : "App Store (sandbox or production)"
    }

    #else

    /// **A Release build has exactly one option.** The rejection risk the Test
    /// Store key carries cannot survive a forgotten checklist item, because
    /// outside DEBUG there is no other key to select and the `test_` literal is
    /// not compiled in.
    static let apiKey = appStoreAPIKey

    static var isUsingTestStore: Bool { false }

    #endif
}
