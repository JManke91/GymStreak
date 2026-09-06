//
//  ReviewPromptTests.swift
//  GymStreakTests
//
//  The automatic App Store rating prompt — the one ask the app makes on its own
//  (docs/rating-prompt.md, docs/acquisition-strategy.md §4.1).
//
//  Four assertions carry the ticket: the ask arrives at the **5th** completed
//  workout and not before; it happens **once, ever**, and the record survives a
//  relaunch; Rule 3 suppresses it inside a session **without consuming it**; and
//  it never lands on the same completion that raises §8 placement B.
//
//  The collision test runs against the **real** `PaywallPresenter`,
//  `ProactivePaywallTriggerStore` and `ProactivePaywallCoordinator` rather than
//  doubles, and drives them in the order `WorkoutViewModel.completeWorkout` does
//  — that ordering *is* the mechanism, and a double that answered "no paywall"
//  would assert it away.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
@MainActor
struct ReviewPromptTests {

    // MARK: - The threshold

    @Test("The rating threshold clears §8 placement B's by construction")
    func reviewPromptThresholdClearsTheValueMoment() {
        // The invariant the whole design rests on: the two triggers count the
        // same workouts, so keeping the thresholds apart is what makes a
        // collision impossible without arbitration. Retuning either one without
        // the other fails here rather than in the App Store.
        #expect(ReviewPromptCoordinator.workoutCount > ProactivePaywallTrigger.valueMomentWorkoutCount)
    }

    @Test("Below the threshold nothing is asked")
    func belowThresholdAsksNothing() async {
        let harness = makeHarness(workoutCount: 4)

        await harness.completeWorkout()

        #expect(harness.reviewPrompt.isRequestDue == false)
        #expect(harness.record.hasRequestedReview == false)
    }

    @Test("The ask arrives on the workout that reaches the threshold")
    func thresholdWorkoutAsks() async {
        // `pauseForCompletion()` stamps `endTime` before the save screen appears,
        // so the count already includes the session that just ended: reaching
        // exactly `workoutCount` means "this is the 5th", not "5 came before it".
        let harness = makeHarness(workoutCount: ReviewPromptCoordinator.workoutCount)

        await harness.completeWorkout()

        #expect(harness.reviewPrompt.isRequestDue)
    }

    @Test("A count past the threshold still asks")
    func laterWorkoutStillAsks() async {
        // A user who installs the update with a long history behind them must
        // not be skipped — the trigger is a floor, not an equality.
        let harness = makeHarness(workoutCount: 40)

        await harness.completeWorkout()

        #expect(harness.reviewPrompt.isRequestDue)
    }

    // MARK: - Once, ever

    @Test("The app asks once and never again")
    func asksOnce() async {
        let harness = makeHarness(workoutCount: 5)

        await harness.completeWorkout()
        harness.reviewPrompt.reviewWasRequested()

        await harness.completeWorkout()
        await harness.completeWorkout()

        #expect(harness.reviewPrompt.isRequestDue == false)
        #expect(harness.record.hasRequestedReview)
    }

    @Test("The record survives a relaunch")
    func recordSurvivesRelaunch() async {
        let defaults = makeDefaults()
        let first = makeHarness(workoutCount: 5, defaults: defaults)

        await first.completeWorkout()
        first.reviewPrompt.reviewWasRequested()

        // A second coordinator over the same defaults is the next launch.
        let second = makeHarness(workoutCount: 5, defaults: defaults)
        await second.completeWorkout()

        #expect(second.reviewPrompt.isRequestDue == false)
    }

    @Test("Reporting an ask that was never due records nothing")
    func reportingWithoutADueRequestRecordsNothing() {
        let harness = makeHarness(workoutCount: 5)

        harness.reviewPrompt.reviewWasRequested()

        #expect(harness.record.hasRequestedReview == false)
    }

    // MARK: - Rule 3

    @Test("Nothing is asked inside an active workout, and nothing is spent")
    func activeWorkoutSuppressesTheAskWithoutConsumingIt() async {
        let harness = makeHarness(workoutCount: 5)

        harness.workout.setWorkoutActive(true)
        await harness.completeWorkout()

        #expect(harness.reviewPrompt.isRequestDue == false)
        #expect(harness.record.hasRequestedReview == false)

        // Deferred, not consumed: the next completion outside a session asks.
        harness.workout.setWorkoutActive(false)
        await harness.completeWorkout()

        #expect(harness.reviewPrompt.isRequestDue)
    }

    // MARK: - No collision with §8 placement B

    @Test("The completion that raises placement B asks for no rating")
    func placementBCompletionAsksForNoRating() async {
        // A free user on the shipped gating switch whose fifth workout is the
        // first completion this install observes: B is earned (count ≥ 3) and
        // raised in the very same turn the rating threshold is met.
        let harness = makeHarness(workoutCount: 5, state: .free, isGatingEnabled: true)

        await harness.completeWorkout()

        #expect(harness.paywalls.pendingPlacement == .valueMoment)
        #expect(harness.reviewPrompt.isRequestDue == false)
        #expect(harness.record.hasRequestedReview == false)
    }

    @Test("The rating prompt arrives once placement B has been spent")
    func ratingArrivesAfterPlacementBIsSpent() async {
        let harness = makeHarness(workoutCount: 5, state: .free, isGatingEnabled: true)

        await harness.completeWorkout()
        harness.showPendingPaywall()
        harness.paywalls.dismiss()

        await harness.completeWorkout()

        #expect(harness.paywalls.pendingPlacement == nil)
        #expect(harness.reviewPrompt.isRequestDue)
    }

    @Test("With gating off the rating prompt still fires")
    func killSwitchOffStillAsks() async {
        let harness = makeHarness(workoutCount: 5, state: .free, isGatingEnabled: false)

        await harness.completeWorkout()

        #expect(harness.paywalls.pendingPlacement == nil)
        #expect(harness.reviewPrompt.isRequestDue)
    }

    // MARK: - Harness

    private struct Harness {
        let reviewPrompt: ReviewPromptCoordinator
        let proactivePaywalls: ProactivePaywallCoordinator
        let paywalls: PaywallPresenter
        let record: ReviewPromptStore
        let workout: ActiveWorkoutRegistry

        /// Exactly what `WorkoutViewModel.completeWorkout` does once the session
        /// is cleared — including the order, which is what keeps the rating
        /// prompt behind the paywall decision.
        ///
        /// `@MainActor` explicitly: a nested type does not inherit the enclosing
        /// suite's isolation.
        @MainActor
        func completeWorkout() async {
            await proactivePaywalls.workoutDidComplete()
            await reviewPrompt.workoutDidComplete()
        }

        /// What `ContentView`'s paywall host does from the sheet's `onAppear` —
        /// the only thing that spends a one-shot placement.
        @MainActor
        func showPendingPaywall() {
            guard let placement = paywalls.pendingPlacement else { return }
            paywalls.didPresent(placement)
        }
    }

    /// - Parameters:
    ///   - workoutCount: the completed-workout count the store reports, i.e. how
    ///     many workouts the user has finished *including* the one that just
    ///     ended.
    ///   - state: an entitled user by default, so §8 placement B can never be
    ///     eligible and the tests that are about the rating rules alone are not
    ///     silently also testing the collision guard. It also pins the other
    ///     half of that guard: `isEligible(.valueMoment)` is false here, and the
    ///     ask must go out rather than wait forever for a paywall this user will
    ///     never be shown.
    private func makeHarness(
        workoutCount: Int,
        state: ProEntitlementState = .subscription,
        isGatingEnabled: Bool = true,
        defaults: UserDefaults? = nil
    ) -> Harness {
        let defaults = defaults ?? makeDefaults()
        let entitlements = StubProEntitlements(state: state)
        let workout = ActiveWorkoutRegistry()
        let paywalls = PaywallPresenter(
            entitlements: entitlements,
            activeWorkout: workout,
            isGatingEnabled: isGatingEnabled,
            defaults: defaults
        )
        let totals = StubCompletedWorkoutCount(count: workoutCount)
        let record = ReviewPromptStore(defaults: defaults)
        return Harness(
            reviewPrompt: ReviewPromptCoordinator(
                record: record,
                totals: totals,
                paywalls: paywalls,
                activeWorkout: workout
            ),
            proactivePaywalls: ProactivePaywallCoordinator(
                entitlements: entitlements,
                paywalls: paywalls,
                triggers: ProactivePaywallTriggerStore(defaults: defaults),
                totals: totals,
                activeWorkout: workout,
                isGatingEnabled: isGatingEnabled
            ),
            paywalls: paywalls,
            record: record,
            workout: workout
        )
    }

    /// A throwaway suite per test: the real presenter, trigger store and review
    /// record all write `UserDefaults.standard`, which the developer's simulator
    /// shares.
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ReviewPromptTests.\(UUID().uuidString)")!
    }
}

// MARK: - Doubles

/// A `LifetimeTrainingTotalsProviding` pinned to one completed-workout count.
///
/// An `actor` because the protocol is `Sendable` — the production conformer is a
/// value type over a `@ModelActor` — the same arrangement `ProactivePaywallTests`
/// uses. Only the count matters here; the aggregation exists solely so placement
/// B can be raised for real in the collision tests.
private actor StubCompletedWorkoutCount: LifetimeTrainingTotalsProviding {

    private let count: Int

    init(count: Int) {
        self.count = count
    }

    func fetchCompletedWorkoutCount() async throws -> Int { count }

    func fetchLifetimeTotals() async throws -> LifetimeTrainingTotals {
        LifetimeTrainingTotals(
            workoutCount: count,
            completedSetCount: count * 12,
            volumeKilograms: Double(count) * 1_000
        )
    }
}
