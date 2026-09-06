//
//  FirstRunCoverOrderTests.swift
//  GymStreakTests
//
//  The order of the three screens that can claim a first launch
//  (docs/onboarding.md, "Cover ordering").
//
//  Two things carry the ticket. **Exactly one cover, in one order**: every
//  combination of the three conditions resolves to the first one that is due,
//  onboarding → Founder thank-you → coach opt-in. And **nothing is dropped by
//  being suppressed**: a condition that turns true while another cover is up —
//  the coach opt-in above all, whose Apple Intelligence availability resolves
//  asynchronously after launch — surfaces on its own afterwards, with nothing
//  spent in the meantime.
//
//  The ordering assertions run against the real `OnboardingFlowViewModel` and
//  `FounderCelebrationCoordinator` over throwaway defaults suites wherever the
//  question is "what was written down", because that is the half a double would
//  assert away.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
@MainActor
struct FirstRunCoverOrderTests {

    // MARK: - Exactly one, in one order

    @Test("The tour comes first, whatever else is due")
    func onboardingWinsOverEverything() {
        for founder in [true, false] {
            for optIn in [true, false] {
                #expect(
                    FirstRunCoverOrder.topmost(
                        isOnboarding: true,
                        isCelebratingFounder: founder,
                        shouldShowCoachOptIn: optIn
                    ) == .onboarding
                )
            }
        }
    }

    @Test("The thank-you comes before the opt-in, once the tour is done")
    func founderWinsOverTheOptIn() {
        #expect(
            FirstRunCoverOrder.topmost(
                isOnboarding: false,
                isCelebratingFounder: true,
                shouldShowCoachOptIn: true
            ) == .founderCelebration
        )
    }

    @Test("The opt-in is shown only when nothing above it is due")
    func optInIsLast() {
        #expect(
            FirstRunCoverOrder.topmost(
                isOnboarding: false,
                isCelebratingFounder: false,
                shouldShowCoachOptIn: true
            ) == .coachOptIn
        )
    }

    @Test("With nothing due the user reaches the tabs")
    func nothingDueShowsTheTabs() {
        #expect(
            FirstRunCoverOrder.topmost(
                isOnboarding: false,
                isCelebratingFounder: false,
                shouldShowCoachOptIn: false
            ) == nil
        )
    }

    @Test("Every combination of conditions names the first cover that is due")
    func everyCombinationNamesOneCover() {
        for onboarding in [true, false] {
            for founder in [true, false] {
                for optIn in [true, false] {
                    let expected: FirstRunCover? =
                        onboarding ? .onboarding
                        : founder ? .founderCelebration
                        : optIn ? .coachOptIn
                        : nil

                    #expect(
                        FirstRunCoverOrder.topmost(
                            isOnboarding: onboarding,
                            isCelebratingFounder: founder,
                            shouldShowCoachOptIn: optIn
                        ) == expected,
                        "onboarding: \(onboarding), founder: \(founder), optIn: \(optIn)"
                    )
                }
            }
        }
    }

    // MARK: - Nothing is dropped by being suppressed

    @Test("An opt-in that becomes eligible during the tour appears afterwards")
    func optInEligibleDuringTheTourIsNotLost() {
        let viewModel = makeOnboarding()

        // Availability resolves while the tour is still on screen: the opt-in is
        // due, and still nothing but the tour is shown.
        #expect(
            FirstRunCoverOrder.topmost(
                isOnboarding: viewModel.isPresenting,
                isCelebratingFounder: false,
                shouldShowCoachOptIn: true
            ) == .onboarding
        )

        viewModel.skip()

        // Nothing re-raised it — the condition is simply read again.
        #expect(
            FirstRunCoverOrder.topmost(
                isOnboarding: viewModel.isPresenting,
                isCelebratingFounder: false,
                shouldShowCoachOptIn: true
            ) == .coachOptIn
        )
    }

    @Test("A thank-you owed during the tour is still owed after it, and unspent")
    func founderScreenIsNotSpentWhileSuppressed() {
        let defaults = makeDefaults()
        let coordinator = makeFounderCoordinator(defaults: defaults)
        let viewModel = makeOnboarding()

        // The launch task resolves the Founder grant while the tour is up.
        coordinator.presentIfDue()

        #expect(coordinator.isPresenting, "the coordinator raises it regardless of what is on screen")
        #expect(
            FirstRunCoverOrder.topmost(
                isOnboarding: viewModel.isPresenting,
                isCelebratingFounder: coordinator.isPresenting,
                shouldShowCoachOptIn: false
            ) == .onboarding,
            "but the tour is what the user sees"
        )
        #expect(!coordinator.hasCelebrated, "a screen nobody saw may not be spent")
        #expect(!FounderCelebrationStore(defaults: defaults).hasCelebrated)

        viewModel.skip()

        #expect(
            FirstRunCoverOrder.topmost(
                isOnboarding: viewModel.isPresenting,
                isCelebratingFounder: coordinator.isPresenting,
                shouldShowCoachOptIn: false
            ) == .founderCelebration
        )
    }

    @Test("The three covers arrive one after another, in order")
    func theThreeCoversArriveInOrder() {
        let coordinator = makeFounderCoordinator()
        let viewModel = makeOnboarding()
        coordinator.presentIfDue()

        func topmost() -> FirstRunCover? {
            FirstRunCoverOrder.topmost(
                isOnboarding: viewModel.isPresenting,
                isCelebratingFounder: coordinator.isPresenting,
                // Available and undecided from the first launch on — the opt-in
                // waits its turn without being asked to.
                shouldShowCoachOptIn: true
            )
        }

        #expect(topmost() == .onboarding)

        viewModel.skip()
        #expect(topmost() == .founderCelebration)

        coordinator.celebrationWasDismissed()
        #expect(topmost() == .coachOptIn)
    }

    // MARK: - The completion flag decides the tour's cover

    @Test("The completion flag is what removes the tour from the order")
    func completionFlagRemovesTheTourFromTheOrder() {
        let defaults = makeDefaults()

        let firstLaunch = makeOnboarding(defaults: defaults)
        #expect(
            FirstRunCoverOrder.topmost(
                isOnboarding: firstLaunch.isPresenting,
                isCelebratingFounder: false,
                shouldShowCoachOptIn: false
            ) == .onboarding
        )

        firstLaunch.skip()

        // The next launch, over the same defaults: a fresh view model reads the
        // flag at composition, so the very first frame goes to the tabs.
        let relaunched = makeOnboarding(defaults: defaults)
        #expect(
            FirstRunCoverOrder.topmost(
                isOnboarding: relaunched.isPresenting,
                isCelebratingFounder: false,
                shouldShowCoachOptIn: false
            ) == nil
        )
    }

    @Test("An unfinished tour still owns the screen on the next launch")
    func anUnfinishedTourReturns() {
        let defaults = makeDefaults()

        // Raised, then the process ends — the app was killed mid-tour.
        _ = makeOnboarding(defaults: defaults)

        let relaunched = makeOnboarding(defaults: defaults)
        #expect(
            FirstRunCoverOrder.topmost(
                isOnboarding: relaunched.isPresenting,
                isCelebratingFounder: true,
                shouldShowCoachOptIn: true
            ) == .onboarding
        )
    }

    // MARK: - Harness

    private func makeOnboarding(defaults: UserDefaults? = nil) -> OnboardingFlowViewModel {
        OnboardingFlowViewModel(
            completion: OnboardingCompletionStore(defaults: defaults ?? makeDefaults()),
            paywalls: PaywallPresenter(
                entitlements: StubProEntitlements(state: .free),
                activeWorkout: ActiveWorkoutRegistry(),
                isGatingEnabled: true,
                defaults: makeDefaults()
            )
        )
    }

    private func makeFounderCoordinator(defaults: UserDefaults? = nil) -> FounderCelebrationCoordinator {
        FounderCelebrationCoordinator(
            entitlements: StubProEntitlements(state: .founder),
            record: FounderCelebrationStore(defaults: defaults ?? makeDefaults()),
            activeWorkout: ActiveWorkoutRegistry(),
            isGatingEnabled: true
        )
    }

    /// A throwaway suite per test: the real stores write `UserDefaults.standard`,
    /// which the developer's simulator shares.
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "FirstRunCoverOrderTests.\(UUID().uuidString)")!
    }
}
