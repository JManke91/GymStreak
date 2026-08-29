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
        guard let key = await harness.cacheKey(for: exercise) else {
            Issue.record("a seeded exercise must produce a cache key")
            return
        }
        harness.cache.deepDives[key] = ExerciseDeepDiveNarrative(workload: "Already yours.")
        harness.spend()

        await harness.viewModel.checkCache(exerciseId: exercise.id, usage: .combined)

        #expect(harness.viewModel.state == .success(narrative: ExerciseDeepDiveNarrative(workload: "Already yours."), isCached: true))
        #expect(harness.allowance.consumeCount == 0)
        #expect(harness.paywalls.presentedPlacements.isEmpty)
    }

    @Test("Asking with nothing left raises the paywall and leaves the button where it was")
    func exhaustedGenerationRaisesThePaywall() async {
        let harness = makeHarness()
        let exercise = harness.seedExercise(completedSets: 6)
        harness.spend()

        let didStart = harness.viewModel.generate(
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            usage: .combined,
            locale: .current
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
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            usage: .combined,
            locale: .current
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
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            usage: .combined,
            locale: .current
        ))
        await harness.viewModel.waitForCurrentGeneration()

        #expect(harness.viewModel.state == .insufficientData)
        #expect(harness.allowance.count(for: .exerciseDeepDive) == 0)
    }

    @Test("A refused regeneration keeps the narrative the user already paid for")
    func refusedRegenerationKeepsTheCache() async {
        let harness = makeHarness()
        let exercise = harness.seedExercise(completedSets: 6)
        guard let key = await harness.cacheKey(for: exercise) else {
            Issue.record("a seeded exercise must produce a cache key")
            return
        }
        harness.cache.deepDives[key] = ExerciseDeepDiveNarrative(workload: "Already yours.")
        harness.spend()

        let didStart = harness.viewModel.regenerate(
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            usage: .combined,
            locale: .current
        )

        #expect(didStart == false)
        #expect(harness.paywalls.presentedPlacements == [.exerciseDeepDive])
        // The gate is asked before the cache is invalidated, so the cached
        // narrative survives the refusal.
        #expect(harness.cache.deepDives[key]?.workload == "Already yours.")
    }

    @Test("With the kill switch off the deep-dive generates unmetered, exactly as before")
    func killSwitchOffGeneratesWithoutMetering() async {
        let harness = makeHarness(isGatingEnabled: false)
        let exercise = harness.seedExercise(completedSets: 6)
        harness.service.isUnavailable = true

        for _ in 0..<3 {
            #expect(harness.viewModel.generate(
                exerciseId: exercise.id,
                exerciseName: exercise.name,
                usage: .combined,
                locale: .current
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
        /// The real model-actor-backed boundary over the same in-memory container the
        /// fixture seeds, not a stub: since ticket 02 every history read the ViewModel
        /// makes crosses it, and a stub would leave that crossing untested.
        let facts: any ExerciseDeepDiveFactProviding
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
            let facts = SwiftDataHistorySnapshotProvider(modelContainer: container, gate: .unshared())
            self.facts = facts
            self.viewModel = ExerciseDeepDiveViewModel(
                allowanceGate: AICoachAllowanceGate(
                    surface: .exerciseDeepDive,
                    entitlements: StubProEntitlements(state: .free),
                    paywalls: paywalls,
                    allowance: allowance,
                    availability: StubAICoachAvailability(),
                    isGatingEnabled: isGatingEnabled
                ),
                facts: facts,
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

        /// The key the ViewModel would cache this exercise's combined narrative under,
        /// assembled from both sides of the boundary exactly as `run` assembles it.
        func cacheKey(for exercise: Exercise) async -> String? {
            await facts.fetchDeepDiveCacheTimestamp(
                exerciseId: exercise.id,
                usageSelection: .combined
            ).map {
                ExerciseDeepDiveViewModel.cacheKey(
                    exerciseId: exercise.id,
                    usageSelection: .combined,
                    timestamp: $0
                )
            }
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
