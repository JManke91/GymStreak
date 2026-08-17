//
//  ProEntitlementTests.swift
//  GymStreakTests
//
//  The Pro entitlement truth source — the composition of the Founder grant with
//  the purchased entitlement — and the free-tier caps. The cap assertions are
//  deliberately literal: they are the numbers docs/monetization-strategy.md
//  §4.2a/§4.4 commits to, so a silent retune fails here and has to be a
//  conscious edit in both places.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
@MainActor
struct ProEntitlementTests {

    // MARK: - State

    @Test("Only .free is free; every other source grants Pro")
    func statesGrantPro() {
        #expect(ProEntitlementState.free.isPro == false)
        #expect(ProEntitlementState.founder.isPro)
        #expect(ProEntitlementState.subscription.isPro)
        #expect(ProEntitlementState.lifetime.isPro)
    }

    // MARK: - Provider

    @Test("The provider reports not-Pro by default")
    func defaultsToFree() {
        let provider = makeProvider()

        #expect(provider.state == .free)
        #expect(provider.isPro == false)
    }

    @Test("Refreshing without a grant or a purchase does not invent an entitlement")
    func refreshKeepsResolvedState() async {
        let founderStatus = StubFounderStatus(isFounder: false)
        let provider = makeProvider(founderStatus: founderStatus)

        await provider.refresh()

        #expect(provider.state == .free)
        #expect(founderStatus.resolveCount == 1)
    }

    @Test("Refreshing surfaces a resolved Founder grant, with its source")
    func refreshReportsFounderGrant() async {
        let provider = makeProvider(founderStatus: StubFounderStatus(isFounder: true))

        await provider.refresh()

        #expect(provider.resolvedState == .founder)
        #expect(provider.isPro)
    }

    // MARK: - Composition with the purchase layer

    @Test(
        "An active purchase is reported with its source",
        arguments: [
            (PurchasedProEntitlement.subscription, ProEntitlementState.subscription),
            (PurchasedProEntitlement.lifetime, ProEntitlementState.lifetime)
        ]
    )
    func purchaseIsReported(
        _ purchased: PurchasedProEntitlement,
        _ expected: ProEntitlementState
    ) async {
        let purchases = StubPurchaseGateway()
        purchases.current = purchased
        let provider = makeProvider(purchases: purchases)

        await provider.refresh()

        #expect(provider.resolvedState == expected)
        #expect(provider.isPro)
    }

    @Test("Founder wins over an active purchase")
    func founderWinsOverPurchase() async {
        let purchases = StubPurchaseGateway()
        purchases.current = .subscription
        let provider = makeProvider(
            founderStatus: StubFounderStatus(isFounder: true),
            purchases: purchases
        )

        await provider.refresh()

        #expect(provider.resolvedState == .founder)
    }

    @Test("A Founder stays Pro when the purchase layer cannot answer at all")
    func founderSurvivesUnavailablePurchaseLayer() async {
        let purchases = StubPurchaseGateway()
        purchases.isUnreachable = true
        let provider = makeProvider(
            founderStatus: StubFounderStatus(isFounder: true),
            purchases: purchases
        )

        await provider.refresh()

        #expect(provider.resolvedState == .founder)
        #expect(provider.isPro)
    }

    @Test("The Founder grant is live before the purchase layer has answered")
    func founderDoesNotWaitOnThePurchaseLayer() async {
        // The offline case that matters: RevenueCat never returns. The grant
        // must not queue behind it — this is why `refresh()` composes twice.
        let purchases = StubPurchaseGateway()
        let neverAnswers = AsyncStream<Void>.makeStream()
        purchases.beforeCurrentEntitlement = { for await _ in neverAnswers.stream {} }
        let provider = makeProvider(
            founderStatus: StubFounderStatus(isFounder: true),
            purchases: purchases
        )

        let refresh = Task { await provider.refresh() }
        await waitUntil(purchases.currentEntitlementCount == 1)

        #expect(provider.resolvedState == .founder)
        #expect(provider.isPro)

        neverAnswers.continuation.finish()
        await refresh.value
    }

    @Test("A purchase is reported even while the Founder resolution has not returned")
    func purchaseDoesNotWaitOnTheFounderResolution() async {
        // The bug this pins (docs/pro-subscription.md §3d): `refresh()` used to
        // await `resolveIfNeeded()` first, and that resolution round-trips
        // StoreKit's `AppTransaction` — which outside production never records a
        // decision, so every call retries it. A refresh fired the instant the
        // user paid therefore never reached the purchase layer at all.
        let founderStatus = StubFounderStatus(isFounder: false)
        let neverResolves = AsyncStream<Void>.makeStream()
        founderStatus.beforeResolve = { for await _ in neverResolves.stream {} }
        let purchases = StubPurchaseGateway()
        purchases.current = .subscription
        let provider = makeProvider(founderStatus: founderStatus, purchases: purchases)

        let refresh = Task { await provider.refresh() }
        await waitUntil(provider.resolvedState == .subscription)

        #expect(provider.isPro)

        neverResolves.continuation.finish()
        await refresh.value
    }

    @Test("A purchase layer that cannot be reached never revokes a live entitlement")
    func unreachablePurchaseLayerDoesNotRevoke() async {
        // `.none` means "this account has no purchase" and legitimately revokes.
        // A failed lookup means nothing at all, and used to revoke too — an
        // offline launch refresh could un-buy a subscription the stream had
        // already delivered.
        let purchases = StubPurchaseGateway()
        let provider = makeProvider(purchases: purchases)
        purchases.emit(.subscription)
        await waitUntil(provider.resolvedState == .subscription)

        purchases.isUnreachable = true
        await provider.refresh()

        #expect(provider.resolvedState == .subscription)
        #expect(provider.isPro)
    }

    @Test("A restore that could not run leaves the entitlement alone")
    func unreachableRestoreDoesNotRevoke() async {
        let purchases = StubPurchaseGateway()
        let provider = makeProvider(purchases: purchases)
        purchases.emit(.lifetime)
        await waitUntil(provider.resolvedState == .lifetime)

        purchases.isUnreachable = true
        await provider.restorePurchases()

        #expect(provider.resolvedState == .lifetime)
    }

    @Test("An entitlement change propagates live, without a refresh or a restart")
    func streamedChangePropagates() async {
        let purchases = StubPurchaseGateway()
        let provider = makeProvider(purchases: purchases)
        #expect(provider.state == .free)

        purchases.emit(.subscription)
        await waitUntil(provider.state == .subscription)
        #expect(provider.resolvedState == .subscription)

        // ... including a lapse, which must drop the entitlement again.
        purchases.emit(.none)
        await waitUntil(provider.state == .free)
        #expect(provider.isPro == false)
    }

    // MARK: - Debug store surface

    @Test("A completed purchase flips the entitlement")
    func purchaseFlipsEntitlement() async {
        let purchases = StubPurchaseGateway()
        purchases.purchaseResult = .purchased
        purchases.current = .lifetime
        let provider = makeProvider(purchases: purchases)

        let result = await provider.purchase(
            ProPurchaseOption(id: "lifetime", displayName: "Lifetime", price: "€79.99")
        )

        #expect(result == .purchased)
        #expect(provider.resolvedState == .lifetime)
    }

    @Test("A cancelled purchase changes nothing and reports no failure")
    func cancelledPurchaseIsNotAFailure() async {
        let purchases = StubPurchaseGateway()
        purchases.purchaseResult = .cancelled
        // Set, but never read: a cancellation must not re-read the entitlement.
        purchases.current = .subscription
        let provider = makeProvider(purchases: purchases)

        let result = await provider.purchase(
            ProPurchaseOption(id: "monthly", displayName: "Monthly", price: "€3.99")
        )

        #expect(result == .cancelled)
        #expect(provider.resolvedState == .free)
        #expect(purchases.currentEntitlementCount == 0)
    }

    @Test("Restoring surfaces a purchase made on another device")
    func restoreSurfacesPurchase() async {
        let purchases = StubPurchaseGateway()
        purchases.restored = .subscription
        let provider = makeProvider(purchases: purchases)

        await provider.restorePurchases()

        #expect(provider.resolvedState == .subscription)
    }

    // MARK: - Debug override

    @Test(
        "A simulated state overrides the resolved one, source included",
        arguments: [ProEntitlementState.founder, .subscription, .lifetime]
    )
    func simulationOverrides(_ simulated: ProEntitlementState) {
        let provider = makeProvider()

        provider.simulatedState = simulated

        #expect(provider.state == simulated)
        #expect(provider.isPro)
        // The resolved entitlement is untouched — simulating is a read-time
        // override, not a grant. It is also what the debug section shows, so a
        // developer can tell which RevenueCat state is being overridden.
        #expect(provider.resolvedState == .free)
    }

    @Test("Simulating free reports not-Pro even from a Pro resolved state")
    func simulationCanDowngrade() {
        let provider = makeProvider(resolvedState: .subscription)

        provider.simulatedState = .free

        #expect(provider.state == .free)
        #expect(provider.isPro == false)
    }

    @Test("Clearing the simulation falls back to the resolved entitlement")
    func clearingSimulationRestoresResolvedState() {
        let provider = makeProvider(
            resolvedState: .founder,
            founderStatus: StubFounderStatus(isFounder: true)
        )
        provider.simulatedState = .free

        provider.simulatedState = nil

        #expect(provider.state == .founder)
        #expect(provider.isPro)
    }

    // MARK: - Caps (§4.2a / §4.4)

    @Test("Free-tier caps report the documented values")
    func capValues() {
        #expect(ProFeatureCaps.freeRoutineLimit == 3)
        #expect(ProFeatureCaps.freeCoachChatMessagesPerMonth == 5)
        #expect(ProFeatureCaps.freePeriodRecapsPerMonth == 1)
        #expect(ProFeatureCaps.freeExerciseDeepDivesPerMonth == 1)
        #expect(ProFeatureCaps.freeChartMetric == .maxWeight)
        #expect(ProFeatureCaps.freeChartTimeframes == [.week, .month, .threeMonths])
        // The chart gate must be a window restriction, not data loss.
        #expect(ProFeatureCaps.freeChartTimeframes.contains(.year) == false)
        #expect(ProFeatureCaps.freeChartTimeframes.contains(.all) == false)
    }

    // MARK: - Kill switch

    /// Asserts `shippedValue`, not `isEnabled`: a developer with
    /// `-PRO_GATING_ON` ticked in the test scheme would otherwise get a red test
    /// for having set up sandbox testing correctly (§9.4a). What must never
    /// change silently is the value a *shipping build* compiles in.
    @Test("Gating ships off")
    func gatingDefaultsOff() {
        #expect(ProGating.shippedValue == false)
    }

    /// The Test Store key is a rejection if it reaches App Review, so a Release
    /// build must have no way to select it — outside DEBUG the literal is not
    /// even compiled in. This asserts what holds in *any* Debug run: the two
    /// keys are distinct and correctly prefixed, and the product list follows
    /// whichever backend is actually live.
    ///
    /// Deliberately **not** asserting `isUsingTestStore == true`. The shared
    /// scheme runs tests with the Run action's launch arguments
    /// (`shouldUseLaunchSchemeArgsEnv`), so a developer who set up sandbox
    /// testing per §9.4a and ticked `-REVENUECAT_APP_STORE` would otherwise get
    /// a red test for having followed the runbook.
    @Test("The store backend follows the build, not a checklist")
    func storeBackendIsStructural() {
        #expect(RevenueCatConfiguration.appStoreAPIKey.hasPrefix("appl_"))
        #expect(RevenueCatConfiguration.testStoreAPIKey.hasPrefix("test_"))
        #expect(RevenueCatConfiguration.appStoreAPIKey != RevenueCatConfiguration.testStoreAPIKey)

        let expected = RevenueCatConfiguration.isUsingTestStore
            ? RevenueCatConfiguration.testStoreProductIdentifiers
            : RevenueCatConfiguration.appStoreProductIdentifiers
        #expect(RevenueCatConfiguration.proProductIdentifiers == expected)
    }
}

// MARK: - Helpers

@MainActor
private func makeProvider(
    resolvedState: ProEntitlementState = .free,
    founderStatus: StubFounderStatus = StubFounderStatus(),
    purchases: StubPurchaseGateway = StubPurchaseGateway()
) -> ProEntitlementProvider {
    ProEntitlementProvider(
        resolvedState: resolvedState,
        founderStatus: founderStatus,
        purchases: purchases
    )
}

/// Lets the provider's own observation task run until `condition` holds.
///
/// Bounded rather than open-ended: everything here is main-actor isolated, so a
/// handful of yields is always enough, and a wrong expectation must fail rather
/// than hang CI.
@MainActor
private func waitUntil(_ condition: @autoclosure () -> Bool) async {
    for _ in 0..<200 {
        if condition() { return }
        await Task.yield()
    }
}

// MARK: - Doubles

/// Stands in for `FounderStatusService` so these tests never reach StoreKit or
/// `UserDefaults.standard`. The service's own branches are covered by
/// `FounderStatusTests`.
@MainActor
private final class StubFounderStatus: FounderStatusResolving {

    var isFounder: Bool
    private(set) var resolveCount = 0

    /// Suspends `resolveIfNeeded()`, standing in for the `AppTransaction`
    /// round-trip the real service performs on every call outside production.
    var beforeResolve: (() async -> Void)?

    init(isFounder: Bool = false) {
        self.isFounder = isFounder
    }

    func resolveIfNeeded() async {
        resolveCount += 1
        await beforeResolve?()
    }
}

/// Stands in for `RevenueCatPurchaseGateway`. Exists for the reason the seam
/// does: `CustomerInfo` cannot be constructed, so the composition branches would
/// otherwise be untestable.
@MainActor
private final class StubPurchaseGateway: ProPurchaseGateway {

    var current: PurchasedProEntitlement = .none
    var restored: PurchasedProEntitlement = .none
    var products: [ProPurchaseOption] = []
    var purchaseResult: ProPurchaseResult = .purchased
    private(set) var currentEntitlementCount = 0

    /// What a purchase layer that could not be reached does — the case
    /// `PurchasedProEntitlement.none` deliberately no longer stands in for.
    struct Unreachable: Error {}

    var isUnreachable = false

    /// Suspends `currentEntitlement()`, so a test can observe the state while
    /// the purchase layer has not answered yet.
    var beforeCurrentEntitlement: (() async -> Void)?

    private var continuation: AsyncStream<PurchasedProEntitlement>.Continuation?

    func entitlementUpdates() -> AsyncStream<PurchasedProEntitlement> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    /// Pushes an update the way `customerInfoStream` would.
    func emit(_ entitlement: PurchasedProEntitlement) {
        continuation?.yield(entitlement)
    }

    func currentEntitlement() async throws -> PurchasedProEntitlement {
        currentEntitlementCount += 1
        await beforeCurrentEntitlement?()
        if isUnreachable { throw Unreachable() }
        return current
    }

    func availableProducts() async -> [ProPurchaseOption] { products }

    func purchase(_ option: ProPurchaseOption) async -> ProPurchaseResult { purchaseResult }

    func restorePurchases() async throws -> PurchasedProEntitlement {
        if isUnreachable { throw Unreachable() }
        return restored
    }
}
