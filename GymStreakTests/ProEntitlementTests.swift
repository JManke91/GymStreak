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
        // What a failed RevenueCat lookup reports: no purchase seen.
        let purchases = StubPurchaseGateway()
        purchases.current = .none
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

    @Test("Gating ships off")
    func gatingDefaultsOff() {
        #expect(ProGating.isEnabled == false)
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

    init(isFounder: Bool = false) {
        self.isFounder = isFounder
    }

    func resolveIfNeeded() async {
        resolveCount += 1
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

    func currentEntitlement() async -> PurchasedProEntitlement {
        currentEntitlementCount += 1
        await beforeCurrentEntitlement?()
        return current
    }

    func availableProducts() async -> [ProPurchaseOption] { products }

    func purchase(_ option: ProPurchaseOption) async -> ProPurchaseResult { purchaseResult }

    func restorePurchases() async -> PurchasedProEntitlement { restored }
}
