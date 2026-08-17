//
//  FounderCelebrationTests.swift
//  GymStreakTests
//
//  The Founder thank-you screen (docs/monetization-strategy.md §7,
//  docs/pro-subscription.md §5h).
//
//  Three assertions carry the ticket: it appears **once, ever**, and the record
//  survives a relaunch; it appears for **nobody but a Founder**, including — the
//  case that matters most — a user whose Founder decision is still undecided;
//  and a moment where it may not be shown (Rule 3, a workout in progress)
//  **defers it rather than spending it**.
//
//  These run against the real `FounderCelebrationStore` over a throwaway
//  defaults suite and the real `ActiveWorkoutRegistry`, because "not spent"
//  is a property of what was written down, and a double would assert it away.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
@MainActor
struct FounderCelebrationTests {

    // MARK: - The Founder sees it, once

    @Test("A Founder is thanked")
    func founderIsThanked() {
        let harness = makeHarness(state: .founder)

        harness.coordinator.presentIfDue()

        #expect(harness.coordinator.isPresenting)
    }

    @Test("The screen appears once and never again")
    func screenAppearsOnceEver() {
        let harness = makeHarness(state: .founder)

        harness.coordinator.presentIfDue()
        harness.coordinator.celebrationWasDismissed()

        harness.coordinator.presentIfDue()
        harness.coordinator.presentIfDue()

        #expect(!harness.coordinator.isPresenting)
        #expect(harness.coordinator.hasCelebrated)
    }

    @Test("The once-ever record survives a relaunch")
    func recordSurvivesRelaunch() {
        let defaults = makeDefaults()
        let first = makeHarness(state: .founder, defaults: defaults)

        first.coordinator.presentIfDue()
        first.coordinator.celebrationWasDismissed()

        // A fresh coordinator and store over the same defaults — the next launch.
        let relaunched = makeHarness(state: .founder, defaults: defaults)
        relaunched.coordinator.presentIfDue()

        #expect(!relaunched.coordinator.isPresenting)
    }

    @Test("A screen that was never dismissed is still owed")
    func screenNobodyDismissedIsNotSpent() {
        let defaults = makeDefaults()
        let first = makeHarness(state: .founder, defaults: defaults)

        // Raised, then the process ends — the app was killed while it was up.
        first.coordinator.presentIfDue()

        let relaunched = makeHarness(state: .founder, defaults: defaults)
        relaunched.coordinator.presentIfDue()

        #expect(relaunched.coordinator.isPresenting)
    }

    @Test("A dismissal reported while nothing is presenting records nothing")
    func strayDismissalRecordsNothing() {
        let harness = makeHarness(state: .founder)

        harness.coordinator.celebrationWasDismissed()

        #expect(!harness.coordinator.hasCelebrated)
        harness.coordinator.presentIfDue()
        #expect(harness.coordinator.isPresenting)
    }

    // MARK: - Nobody else sees it

    @Test(
        "No other entitlement is ever thanked",
        arguments: [ProEntitlementState.free, .subscription, .lifetime]
    )
    func otherEntitlementsSeeNothing(state: ProEntitlementState) {
        let harness = makeHarness(state: state)

        harness.coordinator.presentIfDue()

        #expect(!harness.coordinator.isPresenting)
    }

    @Test("An undecided Founder decision shows nothing and is retried, not spent")
    func undecidedDecisionShowsNothingAndIsRetried() {
        let harness = makeHarness(state: .free)

        // `FounderStatusService` leaves the decision absent when it cannot be
        // resolved (first launch offline, an unverified transaction), so the
        // provider reports `.free` — never a provisional Founder.
        harness.coordinator.presentIfDue()
        #expect(!harness.coordinator.isPresenting)
        #expect(!harness.coordinator.hasCelebrated, "nothing may be written down")

        // The next launch resolves it.
        harness.entitlements.state = .founder
        harness.coordinator.presentIfDue()

        #expect(harness.coordinator.isPresenting)
    }

    // MARK: - Rule 3 — never inside a workout

    @Test("Nothing is shown during an active workout, and nothing is spent")
    func activeWorkoutDefersTheScreen() {
        let harness = makeHarness(state: .founder)
        harness.workout.setWorkoutActive(true)

        harness.coordinator.presentIfDue()

        #expect(!harness.coordinator.isPresenting)
        #expect(!harness.coordinator.hasCelebrated)

        // The next safe moment: the workout ended, the app came back to the
        // foreground.
        harness.workout.setWorkoutActive(false)
        harness.coordinator.presentIfDue()

        #expect(harness.coordinator.isPresenting)
    }

    @Test("A screen deferred by Rule 3 survives a relaunch")
    func deferredScreenSurvivesRelaunch() {
        let defaults = makeDefaults()
        let first = makeHarness(state: .founder, defaults: defaults)
        first.workout.setWorkoutActive(true)
        first.coordinator.presentIfDue()
        #expect(!first.coordinator.isPresenting)

        let relaunched = makeHarness(state: .founder, defaults: defaults)
        relaunched.coordinator.presentIfDue()

        #expect(relaunched.coordinator.isPresenting)
    }

    // MARK: - The kill switch

    @Test("With gating off nothing is shown, and the screen is kept for later")
    func killSwitchOffShowsNothing() {
        let defaults = makeDefaults()
        let gatingOff = makeHarness(state: .founder, isGatingEnabled: false, defaults: defaults)

        gatingOff.coordinator.presentIfDue()

        #expect(!gatingOff.coordinator.isPresenting)
        #expect(!gatingOff.coordinator.hasCelebrated)

        // Ticket 15 flips the switch: the release that starts gating is the one
        // that thanks the Founder, which is the whole point of holding it back.
        let gatingOn = makeHarness(state: .founder, isGatingEnabled: true, defaults: defaults)
        gatingOn.coordinator.presentIfDue()

        #expect(gatingOn.coordinator.isPresenting)
    }

    // MARK: - The debug bypass

    @Test("The debug bypass shows the screen to anyone — but never inside a workout")
    func debugBypassStillHonoursRuleThree() {
        let harness = makeHarness(state: .free, isGatingEnabled: false)

        harness.workout.setWorkoutActive(true)
        harness.coordinator.presentIgnoringEligibility()
        #expect(!harness.coordinator.isPresenting, "Rule 3 is absolute, debug included")

        harness.workout.setWorkoutActive(false)
        harness.coordinator.presentIgnoringEligibility()
        #expect(harness.coordinator.isPresenting)
    }

    @Test("The debug reset clears the record and the mirror together")
    func debugResetClearsBoth() {
        let defaults = makeDefaults()
        let harness = makeHarness(state: .founder, defaults: defaults)

        harness.coordinator.presentIfDue()
        harness.coordinator.celebrationWasDismissed()
        #expect(harness.coordinator.hasCelebrated)

        harness.coordinator.resetCelebration()

        #expect(!harness.coordinator.hasCelebrated)
        harness.coordinator.presentIfDue()
        #expect(harness.coordinator.isPresenting)
        // And the stored record went with it, not just the in-memory mirror.
        #expect(!FounderCelebrationStore(defaults: defaults).hasCelebrated)
    }

    // MARK: - Copy

    @Test("Every string on the screen is localized")
    func screenStringsResolve() {
        let keys = [
            "founder.celebration.eyebrow",
            "founder.celebration.headline",
            "founder.celebration.body",
            "founder.celebration.included1.title",
            "founder.celebration.included1.detail",
            "founder.celebration.included2.title",
            "founder.celebration.included2.detail",
            "founder.celebration.included3.title",
            "founder.celebration.included3.detail",
            "founder.celebration.footer",
            "founder.celebration.cta"
        ]

        for key in keys {
            // A missing entry in Localizable.strings resolves to the key itself.
            #expect(key.localized != key)
        }
    }

    // MARK: - Harness

    private struct Harness {
        let coordinator: FounderCelebrationCoordinator
        let entitlements: StubProEntitlements
        let workout: ActiveWorkoutRegistry
    }

    private func makeHarness(
        state: ProEntitlementState = .free,
        isGatingEnabled: Bool = true,
        defaults: UserDefaults? = nil
    ) -> Harness {
        let entitlements = StubProEntitlements(state: state)
        let workout = ActiveWorkoutRegistry()
        return Harness(
            coordinator: FounderCelebrationCoordinator(
                entitlements: entitlements,
                record: FounderCelebrationStore(defaults: defaults ?? makeDefaults()),
                activeWorkout: workout,
                isGatingEnabled: isGatingEnabled
            ),
            entitlements: entitlements,
            workout: workout
        )
    }

    /// A throwaway suite per test: the real store writes `UserDefaults.standard`,
    /// which the developer's simulator shares.
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "FounderCelebrationTests.\(UUID().uuidString)")!
    }
}
