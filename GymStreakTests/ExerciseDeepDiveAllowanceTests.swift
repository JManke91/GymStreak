//
//  ExerciseDeepDiveAllowanceTests.swift
//  GymStreakTests
//
//  P5 — the Exercise Deep-Dive taster, driven through the real
//  `ExerciseDeepDiveViewModel` over an in-memory SwiftData container.
//  `RecapDeepDiveAllowanceTests` covers the gate itself; this file covers the
//  wiring: what a cache hit costs (nothing), what a refusal leaves on screen,
//  and that every failing exit refunds. Shared doubles live in
//  `Support/AICoachAllowanceTestDoubles.swift`.
//

import Testing
import Foundation
import SwiftData
import FoundationModels
@testable import GymStreak


@Suite
@MainActor
struct ExerciseDeepDiveAllowanceTests {

    @Test("A cached narrative loads with the allowance spent, and costs nothing to re-read")
    func cachedNarrativeIsFreeAndNeverBlocked() async {
        let harness = makeHarness()
        let exercise = harness.seedExercise(completedSets: 6)
        guard let key = harness.viewModel.cacheKey(
            exerciseId: exercise.id,
            modelContext: harness.context
        ) else {
            Issue.record("a seeded exercise must produce a cache key")
            return
        }
        harness.cache.deepDives[key] = ExerciseDeepDiveOutput(narrative: "Already yours.")
        harness.spend()

        await harness.viewModel.checkCache(
            exercise: exercise,
            locale: .current,
            modelContext: harness.context
        )

        #expect(harness.viewModel.state == .success(text: "Already yours.", isCached: true))
        #expect(harness.allowance.consumeCount == 0)
        #expect(harness.paywalls.presentedPlacements.isEmpty)
    }

    @Test("Asking with nothing left raises the paywall and leaves the button where it was")
    func exhaustedGenerationRaisesThePaywall() {
        let harness = makeHarness()
        let exercise = harness.seedExercise(completedSets: 6)
        harness.spend()

        let didStart = harness.viewModel.generate(
            exercise: exercise,
            locale: .current,
            modelContext: harness.context
        )

        #expect(didStart == false)
        #expect(harness.viewModel.state == .idle)
        #expect(harness.paywalls.presentedPlacements == [.exerciseDeepDive])
    }

    @Test("A generation that never started gives the unit back")
    func unstartedGenerationRefunds() async {
        let harness = makeHarness()
        let exercise = harness.seedExercise(completedSets: 6)
        harness.service.isUnavailable = true

        #expect(harness.viewModel.generate(
            exercise: exercise,
            locale: .current,
            modelContext: harness.context
        ))
        await harness.viewModel.waitForCurrentGeneration()

        #expect(harness.viewModel.state == .unavailable)
        #expect(harness.allowance.consumeCount == 1)
        #expect(harness.allowance.count(for: .exerciseDeepDive) == 0)
    }

    @Test("An exercise with too little history costs nothing")
    func insufficientDataRefunds() async {
        let harness = makeHarness()
        // Two completed sets — below the aggregator's four-set floor.
        let exercise = harness.seedExercise(completedSets: 2)

        #expect(harness.viewModel.generate(
            exercise: exercise,
            locale: .current,
            modelContext: harness.context
        ))
        await harness.viewModel.waitForCurrentGeneration()

        #expect(harness.viewModel.state == .insufficientData)
        #expect(harness.allowance.count(for: .exerciseDeepDive) == 0)
    }

    @Test("A refused regeneration keeps the narrative the user already paid for")
    func refusedRegenerationKeepsTheCache() {
        let harness = makeHarness()
        let exercise = harness.seedExercise(completedSets: 6)
        guard let key = harness.viewModel.cacheKey(
            exerciseId: exercise.id,
            modelContext: harness.context
        ) else {
            Issue.record("a seeded exercise must produce a cache key")
            return
        }
        harness.cache.deepDives[key] = ExerciseDeepDiveOutput(narrative: "Already yours.")
        harness.spend()

        let didStart = harness.viewModel.regenerate(
            exercise: exercise,
            locale: .current,
            modelContext: harness.context
        )

        #expect(didStart == false)
        #expect(harness.paywalls.presentedPlacements == [.exerciseDeepDive])
        // The gate is asked before the cache is invalidated, so the cached
        // narrative survives the refusal.
        #expect(harness.cache.deepDives[key]?.narrative == "Already yours.")
    }

    @Test("With the kill switch off the deep-dive generates unmetered, exactly as before")
    func killSwitchOffGeneratesWithoutMetering() async {
        let harness = makeHarness(isGatingEnabled: false)
        let exercise = harness.seedExercise(completedSets: 6)
        harness.service.isUnavailable = true

        for _ in 0..<3 {
            #expect(harness.viewModel.generate(
                exercise: exercise,
                locale: .current,
                modelContext: harness.context
            ))
            await harness.viewModel.waitForCurrentGeneration()
        }

        #expect(harness.allowance.consumeCount == 0)
        #expect(harness.paywalls.presentedPlacements.isEmpty)
    }

    // MARK: - Harness

    @MainActor
    struct Harness {
        let viewModel: ExerciseDeepDiveViewModel
        let context: ModelContext
        let cache: FakeAICoachCache
        let service: FakeAICoachService
        let allowance: SpyAllowanceStore
        let paywalls: RecordingPaywallPresenter
        private let container: ModelContainer

        init(isGatingEnabled: Bool) {
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
            self.viewModel = ExerciseDeepDiveViewModel(
                allowanceGate: AICoachAllowanceGate(
                    surface: .exerciseDeepDive,
                    entitlements: StubProEntitlements(state: .free),
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

        /// Spends the surface's single free generation directly on the store,
        /// so the ViewModel under test starts from an exhausted allowance.
        func spend() {
            for _ in 0..<ProFeatureCaps.freeExerciseDeepDivesPerMonth {
                allowance.consume(.exerciseDeepDive)
            }
            allowance.resetCallCounts()
        }

        @discardableResult
        func seedExercise(completedSets: Int) -> Exercise {
            AICoachHistoryFixture.seedExercise(
                context: context,
                completedSets: completedSets
            )
        }
    }

    func makeHarness(isGatingEnabled: Bool = true) -> Harness {
        Harness(isGatingEnabled: isGatingEnabled)
    }
}
