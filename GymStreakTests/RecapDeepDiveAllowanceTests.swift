//
//  RecapDeepDiveAllowanceTests.swift
//  GymStreakTests
//
//  P4 and P5 — the one-per-calendar-month AI Period Recap and Exercise
//  Deep-Dive tasters (docs/monetization-strategy.md §4.2a P4/P5, §4.3, §7,
//  §8 C/D). The line these tests defend is §4.3's: **AI about one workout is
//  free, AI about your training is Pro**. So three things carry this file: a
//  result already generated is free to re-read forever, a generation the user
//  did not ask for is never charged, and the two free surfaces (Post-Workout
//  Recap, Workout Analysis) stay unmetered.
//
//  This file covers the **gate** for both new surfaces. The two ViewModels'
//  wiring is covered by `PeriodRecapAllowanceTests` and
//  `ExerciseDeepDiveAllowanceTests`; the arithmetic, the store and the kill
//  switch by `CoachChatAllowanceTests`, since all three surfaces share them.
//  Shared doubles live in `Support/AICoachAllowanceTestDoubles.swift`.
//

import Testing
import Foundation
import SwiftData
import FoundationModels
@testable import GymStreak

// MARK: - The gate, for the two new surfaces

@Suite
@MainActor
struct RecapDeepDiveAllowanceTests {

    @Test(
        "One free generation a month, and the second raises the surface's placement",
        arguments: [MeteredAISurface.periodRecap, .exerciseDeepDive]
    )
    func oneFreeGenerationThenPaywall(surface: MeteredAISurface) {
        let harness = makeHarness(surface: surface)

        #expect(harness.gate.requestGeneration()?.didConsume == true)
        #expect(harness.gate.isExhausted)
        #expect(harness.gate.requestGeneration() == nil)

        #expect(harness.paywalls.presentedPlacements == [surface.placement])
        // The refused request consumed nothing.
        #expect(harness.gate.consumedCount == surface.freeMonthlyLimit)
    }

    @Test("The recap, the deep-dive and the chat count against each other not at all")
    func theThreeAllowancesAreIndependent() {
        let store = makeStore()
        let paywalls = RecordingPaywallPresenter()
        let gates = Dictionary(
            uniqueKeysWithValues: MeteredAISurface.allCases.map {
                ($0, makeGate(surface: $0, allowance: store, paywalls: paywalls))
            }
        )

        // Spend the recap's single generation.
        #expect(gates[.periodRecap]?.requestGeneration()?.didConsume == true)

        #expect(gates[.periodRecap]?.isExhausted == true)
        #expect(gates[.exerciseDeepDive]?.isExhausted == false)
        #expect(gates[.coachChat]?.isExhausted == false)
        #expect(gates[.exerciseDeepDive]?.consumedCount == 0)
        #expect(gates[.coachChat]?.remaining == ProFeatureCaps.freeCoachChatMessagesPerMonth)

        // And the deep-dive's own generation leaves the recap where it was.
        #expect(gates[.exerciseDeepDive]?.requestGeneration()?.didConsume == true)
        #expect(gates[.periodRecap]?.consumedCount == 1)
        #expect(paywalls.presentedPlacements.isEmpty)
    }

    @Test(
        "Pro, lifetime and Founder are unmetered on both surfaces",
        arguments: [ProEntitlementState.subscription, .lifetime, .founder]
    )
    func proUsersAreUnmetered(state: ProEntitlementState) {
        for surface in [MeteredAISurface.periodRecap, .exerciseDeepDive] {
            let harness = makeHarness(surface: surface, state: state)

            for _ in 0..<10 {
                #expect(harness.gate.requestGeneration()?.didConsume == false)
            }

            #expect(harness.gate.isMetered == false)
            #expect(harness.gate.isExhausted == false)
            #expect(harness.gate.consumedCount == 0)
            #expect(harness.gate.nudgeState == nil)
            #expect(harness.paywalls.presentedPlacements.isEmpty)
        }
    }

    @Test("A lapsed subscriber returns to one a month, with everything they generated still theirs")
    func lapseReturnsToTheTaster() {
        let harness = makeHarness(surface: .periodRecap, state: .subscription)
        for _ in 0..<10 { _ = harness.gate.requestGeneration() }

        harness.entitlements.state = .free

        // Nothing was counted while they were Pro, so the taster starts whole.
        #expect(harness.gate.consumedCount == 0)
        #expect(harness.gate.remaining == ProFeatureCaps.freePeriodRecapsPerMonth)
        #expect(harness.gate.requestGeneration()?.didConsume == true)
        #expect(harness.gate.requestGeneration() == nil)
        #expect(harness.paywalls.presentedPlacements == [.periodRecap])
    }

    @Test(
        "A device without Apple Intelligence is never paywalled and never metered",
        arguments: [MeteredAISurface.periodRecap, .exerciseDeepDive]
    )
    func unavailableDeviceIsNeverPaywalled(surface: MeteredAISurface) {
        let harness = makeHarness(surface: surface, availability: .deviceNotEligible)

        for _ in 0..<10 {
            #expect(harness.gate.requestGeneration()?.didConsume == false)
        }
        harness.gate.presentPaywallIfExhausted()

        #expect(harness.paywalls.presentedPlacements.isEmpty)
        #expect(harness.gate.isMetered == false)
        #expect(harness.gate.nudgeState == nil)
        #expect(harness.gate.consumedCount == 0)
    }

    @Test(
        "With the kill switch off both surfaces are unmetered and unchanged from today",
        arguments: [MeteredAISurface.periodRecap, .exerciseDeepDive]
    )
    func killSwitchOffBehavesAsBefore(surface: MeteredAISurface) {
        let harness = makeHarness(surface: surface, isGatingEnabled: false)

        for _ in 0..<10 {
            #expect(harness.gate.requestGeneration()?.didConsume == false)
        }
        harness.gate.presentPaywallIfExhausted()

        #expect(harness.gate.isMetered == false)
        #expect(harness.gate.isExhausted == false)
        #expect(harness.gate.nudgeState == nil)
        #expect(harness.gate.consumedCount == 0)
        #expect(harness.paywalls.presentedPlacements.isEmpty)
    }

    @Test(
        "A failed generation gives the unit back",
        arguments: [MeteredAISurface.periodRecap, .exerciseDeepDive]
    )
    func failedGenerationRefunds(surface: MeteredAISurface) {
        let harness = makeHarness(surface: surface)

        guard let ticket = harness.gate.requestGeneration() else {
            Issue.record("the first generation must be allowed")
            return
        }
        #expect(harness.gate.isExhausted)

        harness.gate.refund(ticket)

        #expect(harness.gate.consumedCount == 0)
        #expect(harness.gate.isExhausted == false)
        #expect(harness.gate.requestGeneration()?.didConsume == true)
        #expect(harness.paywalls.presentedPlacements.isEmpty)
    }

    @Test("At a cap of one the nudge is on screen before the generation, not after it")
    func nudgeIsVisibleBeforeTheOnlyFreeGeneration() {
        let harness = makeHarness(surface: .periodRecap)

        // Unlike the chat's five, a cap of one means the *first* generation is
        // also the last — so §8 D's hint has to be there from the start.
        #expect(harness.gate.nudgeState == .lastRemaining(consumed: 0, limit: 1))
        _ = harness.gate.requestGeneration()
        #expect(harness.gate.nudgeState == .exhausted(consumed: 1, limit: 1))
    }

    // MARK: - The free surfaces stay free

    @Test("Only three AI surfaces are metered — the two single-workout ones are not")
    func singleWorkoutSurfacesAreNotMetered() {
        // §4.3's line, as an assertion: AI about *one workout* (the
        // post-workout recap and the workout analysis) is free and unmetered,
        // AI about the user's *training history* is what carries a taster.
        #expect(Set(MeteredAISurface.allCases) == [.coachChat, .periodRecap, .exerciseDeepDive])

        // Neither free surface has a placement, so nothing in the app can raise
        // a paywall from one.
        let placementIdentifiers = Set(PaywallPlacement.allCases.map(\.identifier))
        #expect(placementIdentifiers.contains("post-workout-recap") == false)
        #expect(placementIdentifiers.contains("workout-analysis") == false)
    }

    // MARK: - Harness

    struct Harness {
        let gate: AICoachAllowanceGate
        let entitlements: StubProEntitlements
        let paywalls: RecordingPaywallPresenter
        let store: MonthlyAllowanceStore
    }

    /// Defaults to gating **on**, unlike the shipped app: with the real
    /// `ProGating.isEnabled` every test here would pass by proving the gate is
    /// inert rather than that it is correct.
    func makeHarness(
        surface: MeteredAISurface,
        state: ProEntitlementState = .free,
        availability: AICoachAvailabilityState = .available,
        isGatingEnabled: Bool = true
    ) -> Harness {
        let entitlements = StubProEntitlements(state: state)
        let paywalls = RecordingPaywallPresenter()
        let store = makeStore()
        return Harness(
            gate: AICoachAllowanceGate(
                surface: surface,
                entitlements: entitlements,
                paywalls: paywalls,
                allowance: store,
                availability: StubAICoachAvailability(state: availability),
                isGatingEnabled: isGatingEnabled
            ),
            entitlements: entitlements,
            paywalls: paywalls,
            store: store
        )
    }

    private func makeGate(
        surface: MeteredAISurface,
        allowance: any MonthlyAllowanceTracking,
        paywalls: RecordingPaywallPresenter
    ) -> AICoachAllowanceGate {
        AICoachAllowanceGate(
            surface: surface,
            entitlements: StubProEntitlements(state: .free),
            paywalls: paywalls,
            allowance: allowance,
            availability: StubAICoachAvailability(),
            isGatingEnabled: true
        )
    }

    /// A throwaway suite per store — the real one writes the App Group suite,
    /// which every other test and the developer's simulator share.
    private func makeStore() -> MonthlyAllowanceStore {
        MonthlyAllowanceStore(
            defaults: UserDefaults(suiteName: "RecapDeepDiveAllowanceTests.\(UUID().uuidString)")!,
            cloud: NoopAllowanceCloudStore(),
            calendar: .current,
            now: { Date() }
        )
    }
}
