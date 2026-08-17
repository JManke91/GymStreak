//
//  PeriodRecapAllowanceTests.swift
//  GymStreakTests
//
//  P4 — the AI Period Recap taster, driven through the real
//  `PeriodRecapViewModel` over an in-memory SwiftData container. The assertion
//  that carries this file: **opening the screen offers the generation instead
//  of spending it** — including when the user got here from the proactive
//  month-boundary prompt. Shared doubles live in
//  `Support/AICoachAllowanceTestDoubles.swift`.
//

import Testing
import Foundation
import SwiftData
import FoundationModels
@testable import GymStreak


@Suite
@MainActor
struct PeriodRecapAllowanceTests {

    @Test("Opening the recap offers the generation instead of spending it")
    func openingTheScreenOffersRatherThanSpending() async {
        let harness = makeHarness()
        harness.seedSessions(count: 3)

        await harness.viewModel.load(modelContext: harness.context)
        await harness.viewModel.waitForCurrentGeneration()

        guard case .offer = harness.viewModel.state else {
            Issue.record("expected .offer, got \(harness.viewModel.state)")
            return
        }
        // The point of the offer: arriving here — including by following the
        // proactive month-boundary prompt — costs nothing.
        #expect(harness.allowance.consumeCount == 0)
        #expect(harness.paywalls.presentedPlacements.isEmpty)
        #expect(harness.viewModel.allowanceNudge?.limit == ProFeatureCaps.freePeriodRecapsPerMonth)
    }

    @Test("Tapping generate spends the month's recap, and a failed one gives it back")
    func generateNowConsumesAndRefundsOnFailure() async {
        let harness = makeHarness()
        harness.seedSessions(count: 3)
        harness.service.isUnavailable = true

        await harness.viewModel.generateNow(modelContext: harness.context)
        await harness.viewModel.waitForCurrentGeneration()

        guard case .unavailable = harness.viewModel.state else {
            Issue.record("expected .unavailable, got \(harness.viewModel.state)")
            return
        }
        #expect(harness.allowance.consumeCount == 1)
        #expect(harness.allowance.count(for: .periodRecap) == 0)
    }

    @Test("Opening with nothing left gates the screen and raises the placement")
    func exhaustedOpenGatesAndPaywalls() async {
        let harness = makeHarness()
        harness.seedSessions(count: 3)
        harness.spend()

        await harness.viewModel.load(modelContext: harness.context)
        await harness.viewModel.waitForCurrentGeneration()

        guard case .gated = harness.viewModel.state else {
            Issue.record("expected .gated, got \(harness.viewModel.state)")
            return
        }
        #expect(harness.paywalls.presentedPlacements == [.periodRecap])
        #expect(harness.allowance.consumeCount == 0)
    }

    @Test("A recap already generated stays readable with the allowance spent")
    func cachedRecapIsFreeAndNeverBlocked() async {
        let harness = makeHarness()
        harness.seedSessions(count: 3)
        harness.cache.periodRecap = PeriodRecapOutput(
            headline: "Already yours.",
            trendsNarrative: "…",
            correlationHighlight: nil,
            closingSentence: "…"
        )
        harness.spend()

        await harness.viewModel.load(modelContext: harness.context)
        await harness.viewModel.waitForCurrentGeneration()

        guard case .success(let output, let isCached, _, _) = harness.viewModel.state else {
            Issue.record("expected .success, got \(harness.viewModel.state)")
            return
        }
        #expect(output.headline == "Already yours.")
        #expect(isCached)
        #expect(harness.paywalls.presentedPlacements.isEmpty)
        #expect(harness.allowance.consumeCount == 0)
    }

    @Test("With the kill switch off the recap generates on open, exactly as before")
    func killSwitchOffGeneratesOnOpen() async {
        let harness = makeHarness(isGatingEnabled: false)
        harness.seedSessions(count: 3)
        harness.service.isUnavailable = true

        await harness.viewModel.load(modelContext: harness.context)
        await harness.viewModel.waitForCurrentGeneration()

        // Not `.offer`: an unmetered user never sees the confirmation step.
        guard case .unavailable = harness.viewModel.state else {
            Issue.record("expected .unavailable, got \(harness.viewModel.state)")
            return
        }
        #expect(harness.allowance.consumeCount == 0)
        #expect(harness.paywalls.presentedPlacements.isEmpty)
    }

    @Test("A Pro user generates on open and is never offered or gated")
    func proUserGeneratesOnOpen() async {
        let harness = makeHarness(state: .subscription)
        harness.seedSessions(count: 3)
        harness.service.isUnavailable = true

        await harness.viewModel.load(modelContext: harness.context)
        await harness.viewModel.waitForCurrentGeneration()

        guard case .unavailable = harness.viewModel.state else {
            Issue.record("expected .unavailable, got \(harness.viewModel.state)")
            return
        }
        #expect(harness.viewModel.allowanceNudge == nil)
        #expect(harness.allowance.consumeCount == 0)
    }

    // MARK: - Harness

    @MainActor
    struct Harness {
        let viewModel: PeriodRecapViewModel
        let context: ModelContext
        let cache: FakeAICoachCache
        let service: FakeAICoachService
        let allowance: SpyAllowanceStore
        let paywalls: RecordingPaywallPresenter
        private let container: ModelContainer

        init(state: ProEntitlementState, isGatingEnabled: Bool) {
            let container = InMemoryModelContainer.make()
            self.container = container
            self.context = ModelContext(container)
            let cache = FakeAICoachCache()
            let service = FakeAICoachService()
            let allowance = SpyAllowanceStore()
            let paywalls = RecordingPaywallPresenter()
            self.cache = cache
            self.service = service
            self.allowance = allowance
            self.paywalls = paywalls
            self.viewModel = PeriodRecapViewModel(
                // `.thisYear` so the seeded sessions cannot fall outside the
                // window on the first day of a week or a month.
                initialRange: .thisYear,
                allowanceGate: AICoachAllowanceGate(
                    surface: .periodRecap,
                    entitlements: StubProEntitlements(state: state),
                    paywalls: paywalls,
                    allowance: allowance,
                    availability: StubAICoachAvailability(),
                    isGatingEnabled: isGatingEnabled
                ),
                service: service,
                cache: cache,
                preferences: FakeAICoachPreferences(),
                availability: StubAICoachAvailability()
            )
        }

        func spend() {
            for _ in 0..<ProFeatureCaps.freePeriodRecapsPerMonth {
                allowance.consume(.periodRecap)
            }
            allowance.resetCallCounts()
        }

        /// The aggregator narrates only from three sessions up; below that the
        /// screen short-circuits to `.insufficient` before reaching the meter.
        func seedSessions(count: Int) {
            AICoachHistoryFixture.seedSessions(context: context, count: count)
        }
    }

    func makeHarness(
        state: ProEntitlementState = .free,
        isGatingEnabled: Bool = true
    ) -> Harness {
        Harness(state: state, isGatingEnabled: isGatingEnabled)
    }
}
