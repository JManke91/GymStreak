//
//  ProactivePaywallTests.swift
//  GymStreakTests
//
//  §8 placements A and B — the two paywalls that fire on their own rather than
//  on a blocked action (docs/monetization-strategy.md §8, docs/pro-subscription.md §5g).
//
//  Three assertions carry the ticket: each placement fires **once, ever**, and
//  the record survives a relaunch; a trigger that becomes true inside a workout
//  is **deferred and not consumed** (Rule 3 is absolute, but §8 B is precisely
//  the moment most likely to arrive mid-session); and with the kill switch off
//  nothing arms, nothing fires, and the unbounded history read never happens.
//
//  These run against the **real** `PaywallPresenter` and `ActiveWorkoutRegistry`
//  rather than `RecordingPaywallPresenter`, deliberately: the deferral and the
//  one-shot are interactions between the coordinator's armed record and the
//  presenter's suppression, so a double that presents everything would assert
//  the mechanism away. The eligibility rules themselves stay covered once, in
//  `PaywallPresentationTests`.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
@MainActor
struct ProactivePaywallTests {

    // MARK: - Placement A — after the first routine is created

    @Test("Creating a routine raises placement A")
    func firstRoutineCreationRaisesPlacementA() async {
        let harness = makeHarness()

        await harness.coordinator.routineWasCreated()

        #expect(harness.presenter.pendingPlacement == .firstRoutineCreated)
        // A carries no endowed figures, so it must not have paid for the
        // unbounded history read.
        #expect(await harness.totals.fetchCount == 0)
    }

    @Test("Placement A fires once, ever")
    func placementAFiresOnce() async {
        let harness = makeHarness()

        await harness.coordinator.routineWasCreated()
        harness.showPendingPaywall()
        harness.presenter.dismiss()

        await harness.coordinator.routineWasCreated()
        await harness.coordinator.routineWasCreated()

        #expect(harness.presenter.pendingPlacement == nil)
    }

    @Test("Placement A's once-ever record survives a relaunch")
    func placementAOneShotSurvivesRelaunch() async {
        let defaults = makeDefaults()
        let first = makeHarness(defaults: defaults)

        await first.coordinator.routineWasCreated()
        first.showPendingPaywall()
        first.presenter.dismiss()

        // A fresh presenter, store and coordinator over the same defaults — the
        // next launch.
        let relaunched = makeHarness(defaults: defaults)
        await relaunched.coordinator.routineWasCreated()

        #expect(relaunched.presenter.pendingPlacement == nil)
    }

    // MARK: - Placement B — whichever of the two lands first

    @Test("The third completed workout raises the value moment; the first two do not")
    func thirdCompletedWorkoutRaisesTheValueMoment() async {
        let harness = makeHarness(totals: totals(workouts: 1))

        await harness.coordinator.workoutDidComplete()
        #expect(harness.presenter.pendingPlacement == nil)

        await harness.totals.set(totals(workouts: 2))
        await harness.coordinator.workoutDidComplete()
        #expect(harness.presenter.pendingPlacement == nil)

        await harness.totals.set(totals(workouts: 3))
        await harness.coordinator.workoutDidComplete()
        #expect(harness.presenter.pendingPlacement == .valueMoment)
    }

    @Test("The first overload suggestion raises the value moment before three workouts")
    func firstOverloadSuggestionRaisesTheValueMoment() async {
        let harness = makeHarness(totals: totals(workouts: 1))

        // The suggestion appears mid-session, which is where it always appears.
        harness.workout.setWorkoutActive(true)
        await harness.coordinator.overloadSuggestionWasShown()
        #expect(harness.presenter.pendingPlacement == nil, "Rule 3 forbids it here")

        harness.workout.setWorkoutActive(false)
        await harness.coordinator.activeWorkoutDidEnd()

        #expect(harness.presenter.pendingPlacement == .valueMoment)
        // One workout logged: the trigger came from the suggestion, not the count.
        #expect(harness.coordinator.valueMomentTotals?.workoutCount == 1)
    }

    @Test("Placement B fires once, ever — a fourth workout raises nothing")
    func valueMomentFiresOnce() async {
        let harness = makeHarness(totals: totals(workouts: 3))

        await harness.coordinator.workoutDidComplete()
        harness.showPendingPaywall()
        harness.presenter.dismiss()

        await harness.totals.set(totals(workouts: 4))
        await harness.coordinator.workoutDidComplete()

        #expect(harness.presenter.pendingPlacement == nil)
    }

    @Test("Placement B's once-ever record survives a relaunch")
    func valueMomentOneShotSurvivesRelaunch() async {
        let defaults = makeDefaults()
        let first = makeHarness(defaults: defaults, totals: totals(workouts: 3))

        await first.coordinator.workoutDidComplete()
        first.showPendingPaywall()
        first.presenter.dismiss()

        let relaunched = makeHarness(defaults: defaults, totals: totals(workouts: 9))
        await relaunched.coordinator.workoutDidComplete()

        #expect(relaunched.presenter.pendingPlacement == nil)
    }

    @Test("The threshold is retunable", arguments: [1, 5])
    func valueMomentThresholdIsRetunable(threshold: Int) async {
        let harness = makeHarness(
            totals: totals(workouts: threshold - 1),
            valueMomentWorkoutCount: threshold
        )

        await harness.coordinator.workoutDidComplete()
        #expect(harness.presenter.pendingPlacement == nil)

        await harness.totals.set(totals(workouts: threshold))
        await harness.coordinator.workoutDidComplete()
        #expect(harness.presenter.pendingPlacement == .valueMoment)
    }

    // MARK: - Rule 3: deferred, never consumed

    @Test("A trigger armed inside a workout is deferred to the end of the session")
    func triggerArmedDuringAWorkoutIsDeferred() async {
        let harness = makeHarness(totals: totals(workouts: 1))

        harness.workout.setWorkoutActive(true)
        await harness.coordinator.overloadSuggestionWasShown()

        #expect(harness.presenter.pendingPlacement == nil)
        // Armed, and *not* spent: the once-ever record is written on
        // presentation, so a suppressed request costs the placement nothing.
        #expect(harness.triggers.isArmed(.valueMoment))
        #expect(harness.presenter.hasPresented(.valueMoment) == false)

        harness.workout.setWorkoutActive(false)
        await harness.coordinator.activeWorkoutDidEnd()

        #expect(harness.presenter.pendingPlacement == .valueMoment)
    }

    @Test("A completion reported while a workout is still running is deferred, not lost")
    func suppressedCompletionIsDeferred() async {
        let harness = makeHarness(totals: totals(workouts: 3))

        harness.workout.setWorkoutActive(true)
        await harness.coordinator.workoutDidComplete()

        #expect(harness.presenter.pendingPlacement == nil)
        #expect(harness.triggers.isArmed(.valueMoment))

        harness.workout.setWorkoutActive(false)
        await harness.coordinator.activeWorkoutDidEnd()

        #expect(harness.presenter.pendingPlacement == .valueMoment)
    }

    @Test("A deferred trigger survives a relaunch")
    func deferredTriggerSurvivesRelaunch() async {
        let defaults = makeDefaults()
        let first = makeHarness(defaults: defaults, totals: totals(workouts: 1))

        first.workout.setWorkoutActive(true)
        await first.coordinator.overloadSuggestionWasShown()
        #expect(first.presenter.pendingPlacement == nil)

        // The app was killed mid-workout and relaunched.
        let relaunched = makeHarness(defaults: defaults, totals: totals(workouts: 1))
        #expect(relaunched.triggers.isArmed(.valueMoment))

        await relaunched.coordinator.activeWorkoutDidEnd()

        #expect(relaunched.presenter.pendingPlacement == .valueMoment)
    }

    @Test("Only one placement is raised per safe moment, and the other is not lost")
    func onlyOnePlacementPerSafeMoment() async {
        let harness = makeHarness(totals: totals(workouts: 3))

        harness.workout.setWorkoutActive(true)
        await harness.coordinator.routineWasCreated()
        await harness.coordinator.workoutDidComplete()
        harness.workout.setWorkoutActive(false)

        await harness.coordinator.activeWorkoutDidEnd()
        // §8 calls B the highest-value placement, so it goes first.
        #expect(harness.presenter.pendingPlacement == .valueMoment)
        harness.showPendingPaywall()
        harness.presenter.dismiss()

        await harness.coordinator.activeWorkoutDidEnd()
        #expect(harness.presenter.pendingPlacement == .firstRoutineCreated)
    }

    // MARK: - Who never sees either

    @Test(
        "A Pro user is never shown either placement, and never pays for the read",
        arguments: [ProEntitlementState.subscription, .lifetime, .founder]
    )
    func proUsersSeeNeither(state: ProEntitlementState) async {
        let harness = makeHarness(state: state, totals: totals(workouts: 9))

        await harness.coordinator.routineWasCreated()
        await harness.coordinator.overloadSuggestionWasShown()
        await harness.coordinator.workoutDidComplete()

        #expect(harness.presenter.pendingPlacement == nil)
        #expect(harness.triggers.isArmed(.firstRoutineCreated) == false)
        #expect(harness.triggers.isArmed(.valueMoment) == false)
        #expect(await harness.totals.fetchCount == 0)
        #expect(await harness.totals.countReadCount == 0)
    }

    @Test("With the kill switch off nothing arms, nothing fires, and nothing is read")
    func killSwitchOffFiresNothing() async {
        let harness = makeHarness(isGatingEnabled: false, totals: totals(workouts: 9))

        await harness.coordinator.routineWasCreated()
        await harness.coordinator.overloadSuggestionWasShown()
        await harness.coordinator.workoutDidComplete()
        await harness.coordinator.activeWorkoutDidEnd()

        #expect(harness.presenter.pendingPlacement == nil)
        #expect(harness.triggers.isArmed(.firstRoutineCreated) == false)
        #expect(harness.triggers.isArmed(.valueMoment) == false)
        // The load-bearing half: with gating off, every user's workout
        // completion would otherwise hit the history store to feed a paywall
        // that can never appear.
        #expect(await harness.totals.fetchCount == 0)
        #expect(await harness.totals.countReadCount == 0)
    }

    // MARK: - The figures

    @Test("Placement B carries the user's real totals")
    func valueMomentCarriesRealTotals() async {
        let real = LifetimeTrainingTotals(
            workoutCount: 7,
            completedSetCount: 143,
            volumeKilograms: 24_312.5
        )
        let harness = makeHarness(totals: real)

        await harness.coordinator.workoutDidComplete()

        #expect(harness.presenter.pendingPlacement == .valueMoment)
        #expect(harness.coordinator.valueMomentTotals == real)
    }

    @Test("A completed workout invalidates the figures rather than reusing them")
    func completionInvalidatesCachedFigures() async {
        let harness = makeHarness(totals: totals(workouts: 2, sets: 40))

        // Arm B from a suggestion so the figures get loaded and cached before
        // the next workout lands.
        harness.workout.setWorkoutActive(true)
        await harness.coordinator.overloadSuggestionWasShown()
        harness.workout.setWorkoutActive(false)
        await harness.coordinator.activeWorkoutDidEnd()
        #expect(harness.coordinator.valueMomentTotals?.workoutCount == 2)
        // Raised but never shown, so the placement is still owed.
        harness.presenter.dismiss()

        await harness.totals.set(totals(workouts: 3, sets: 61))
        await harness.coordinator.workoutDidComplete()

        #expect(harness.presenter.pendingPlacement == .valueMoment)
        // The stale two-workout read must not be what the paywall shows.
        #expect(harness.coordinator.valueMomentTotals?.workoutCount == 3)
        #expect(harness.coordinator.valueMomentTotals?.completedSetCount == 61)
    }

    @Test("A failed read defers placement B instead of showing it without figures")
    func failedReadDefersTheValueMoment() async {
        let harness = makeHarness(totals: totals(workouts: 1))
        await harness.totals.setFailing(true)

        // Armed by a suggestion, so the raise does not depend on the count.
        harness.workout.setWorkoutActive(true)
        await harness.coordinator.overloadSuggestionWasShown()
        harness.workout.setWorkoutActive(false)

        await harness.coordinator.activeWorkoutDidEnd()

        #expect(harness.presenter.pendingPlacement == nil)
        #expect(harness.coordinator.valueMomentTotals == nil)
        #expect(harness.triggers.isArmed(.valueMoment), "still armed, still owed")

        await harness.totals.setFailing(false)
        await harness.coordinator.activeWorkoutDidEnd()

        #expect(harness.presenter.pendingPlacement == .valueMoment)
        #expect(harness.coordinator.valueMomentTotals != nil)
    }

    @Test("Workouts below the threshold cost a count, never the whole-history aggregation")
    func belowThresholdCostsOnlyACount() async {
        let harness = makeHarness(totals: totals(workouts: 1))

        await harness.coordinator.workoutDidComplete()
        await harness.totals.set(totals(workouts: 2))
        await harness.coordinator.workoutDidComplete()

        #expect(harness.presenter.pendingPlacement == nil)
        #expect(await harness.totals.countReadCount == 2)
        // The aggregation shares one model actor with the History tab's own
        // post-workout refetch, so it must not run for a workout that cannot
        // possibly earn the placement.
        #expect(await harness.totals.fetchCount == 0)

        await harness.totals.set(totals(workouts: 3))
        await harness.coordinator.workoutDidComplete()

        #expect(harness.presenter.pendingPlacement == .valueMoment)
        #expect(await harness.totals.fetchCount == 1)
    }

    @Test("The figures are read once and reused until a workout changes them")
    func figuresAreReadOncePerSafeMoment() async {
        let harness = makeHarness(totals: totals(workouts: 1))

        harness.workout.setWorkoutActive(true)
        await harness.coordinator.overloadSuggestionWasShown()
        harness.workout.setWorkoutActive(false)

        await harness.coordinator.activeWorkoutDidEnd()
        await harness.coordinator.activeWorkoutDidEnd()

        #expect(await harness.totals.fetchCount == 1)
    }

    // MARK: - Harness

    private struct Harness {
        let coordinator: ProactivePaywallCoordinator
        let presenter: PaywallPresenter
        let workout: ActiveWorkoutRegistry
        let triggers: ProactivePaywallTriggerStore
        let entitlements: StubProEntitlements
        let totals: StubLifetimeTotalsProvider

        /// What `ContentView`'s host does from the sheet's `onAppear` — and the
        /// only thing that spends a one-shot.
        ///
        /// `@MainActor` explicitly: a nested type does not inherit the enclosing
        /// suite's isolation.
        @MainActor
        func showPendingPaywall() {
            guard let placement = presenter.pendingPlacement else { return }
            presenter.didPresent(placement)
        }
    }

    private func makeHarness(
        state: ProEntitlementState = .free,
        isGatingEnabled: Bool = true,
        defaults: UserDefaults? = nil,
        totals: LifetimeTrainingTotals = LifetimeTrainingTotals(
            workoutCount: 0,
            completedSetCount: 0,
            volumeKilograms: 0
        ),
        valueMomentWorkoutCount: Int = ProactivePaywallTrigger.valueMomentWorkoutCount
    ) -> Harness {
        let defaults = defaults ?? makeDefaults()
        let entitlements = StubProEntitlements(state: state)
        let workout = ActiveWorkoutRegistry()
        let presenter = PaywallPresenter(
            entitlements: entitlements,
            activeWorkout: workout,
            isGatingEnabled: isGatingEnabled,
            defaults: defaults
        )
        let triggers = ProactivePaywallTriggerStore(defaults: defaults)
        let totalsProvider = StubLifetimeTotalsProvider(totals: totals)
        return Harness(
            coordinator: ProactivePaywallCoordinator(
                entitlements: entitlements,
                paywalls: presenter,
                triggers: triggers,
                totals: totalsProvider,
                activeWorkout: workout,
                isGatingEnabled: isGatingEnabled,
                valueMomentWorkoutCount: valueMomentWorkoutCount
            ),
            presenter: presenter,
            workout: workout,
            triggers: triggers,
            entitlements: entitlements,
            totals: totalsProvider
        )
    }

    /// A throwaway suite per test: the real presenter and trigger store write
    /// `UserDefaults.standard`, which the developer's simulator shares.
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ProactivePaywallTests.\(UUID().uuidString)")!
    }

    private func totals(workouts: Int, sets: Int = 0) -> LifetimeTrainingTotals {
        LifetimeTrainingTotals(
            workoutCount: workouts,
            completedSetCount: sets,
            volumeKilograms: Double(workouts) * 1_000
        )
    }
}

// MARK: - Doubles

/// A `LifetimeTrainingTotalsProviding` that counts its reads.
///
/// An `actor` because the protocol is `Sendable` (the production conformer is a
/// value type over a `@ModelActor`), the same arrangement as
/// `ChartGatingTests`' history stub. The read count is the assertion behind "the
/// kill switch off costs nothing" and "the figures are not re-read per raise".
private actor StubLifetimeTotalsProvider: LifetimeTrainingTotalsProviding {

    /// Calls to the **aggregation**. Kept apart from `countReadCount` because
    /// the whole point of the split is that the trigger check never pays for it.
    private(set) var fetchCount = 0
    private(set) var countReadCount = 0
    private var totals: LifetimeTrainingTotals
    private var isFailing = false

    init(totals: LifetimeTrainingTotals) {
        self.totals = totals
    }

    func fetchCompletedWorkoutCount() async throws -> Int {
        countReadCount += 1
        if isFailing { throw StubError.unavailable }
        return totals.workoutCount
    }

    func fetchLifetimeTotals() async throws -> LifetimeTrainingTotals {
        fetchCount += 1
        if isFailing { throw StubError.unavailable }
        return totals
    }

    func set(_ totals: LifetimeTrainingTotals) {
        self.totals = totals
    }

    func setFailing(_ isFailing: Bool) {
        self.isFailing = isFailing
    }

    enum StubError: Error { case unavailable }
}
