//
//  PaywallPresentationTests.swift
//  GymStreakTests
//
//  The paywall presentation seam: the four eligibility rules the presenter
//  enforces so nine call sites don't have to. The Rule 3 assertion is the
//  load-bearing one — an upsell inside a workout is the rage-uninstall failure
//  mode docs/monetization-strategy.md §8 prohibits outright.
//  The placement taxonomy itself is covered by `PaywallPlacementTests`.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
@MainActor
struct PaywallPresentationTests {

    // MARK: - Rule 3

    @Test("Rule 3: nothing presents during an active workout session")
    func suppressedDuringWorkout() {
        let workout = StubActiveWorkout()
        let presenter = makePresenter(activeWorkout: workout)

        workout.setWorkoutActive(true)
        presenter.present(.routineCap)

        #expect(presenter.pendingPlacement == nil)

        workout.setWorkoutActive(false)
        presenter.present(.routineCap)

        #expect(presenter.pendingPlacement == .routineCap)
    }

    @Test("A one-shot suppressed by Rule 3 is not spent")
    func suppressedOneShotIsNotBurned() {
        let workout = StubActiveWorkout()
        let presenter = makePresenter(activeWorkout: workout)

        workout.setWorkoutActive(true)
        presenter.present(.valueMoment)
        workout.setWorkoutActive(false)

        #expect(presenter.hasPresented(.valueMoment) == false)

        presenter.present(.valueMoment)

        #expect(presenter.pendingPlacement == .valueMoment)
    }

    // MARK: - Raised is not presented

    @Test("A one-shot that was raised but never appeared is not spent")
    func raisedButUnseenOneShotIsNotBurned() {
        let presenter = makePresenter()

        // What a full-screen cover over the app root produces: the placement is
        // pending, but the host never reports it on screen.
        presenter.present(.valueMoment)

        #expect(presenter.pendingPlacement == .valueMoment)
        #expect(presenter.hasPresented(.valueMoment) == false)
    }

    @Test("A request the host could not show is replaced, not wedged")
    func unseenRequestDoesNotWedgeTheSeam() {
        let presenter = makePresenter()

        presenter.present(.valueMoment)
        presenter.present(.routineCap)

        #expect(presenter.pendingPlacement == .routineCap)
    }

    @Test("Rule 3 holds even on the debug bypass")
    func debugBypassKeepsRuleThree() {
        let workout = StubActiveWorkout()
        let presenter = makePresenter(activeWorkout: workout, isGatingEnabled: false)

        workout.setWorkoutActive(true)
        presenter.presentIgnoringEligibility(.chartWindow)

        #expect(presenter.pendingPlacement == nil)
    }

    // MARK: - The kill switch

    @Test("With gating off, no placement presents")
    func killSwitchSuppressesEverything() {
        let presenter = makePresenter(isGatingEnabled: false)

        for placement in PaywallPlacement.allCases {
            presenter.present(placement)
            #expect(presenter.pendingPlacement == nil)
        }
    }

    @Test("The debug surface can still raise a placement with gating off")
    func debugBypassPresentsWithGatingOff() {
        let presenter = makePresenter(isGatingEnabled: false)

        presenter.presentIgnoringEligibility(.coachChat)

        #expect(presenter.pendingPlacement == .coachChat)
    }

    // MARK: - Entitlement

    @Test("A Pro user is never shown a paywall")
    func proUserIsNeverPaywalled() {
        let presenter = makePresenter(entitlements: StubEntitlements(state: .subscription))

        presenter.present(.routineCap)

        #expect(presenter.pendingPlacement == nil)
    }

    @Test("A Founder is never shown a paywall")
    func founderIsNeverPaywalled() {
        let presenter = makePresenter(entitlements: StubEntitlements(state: .founder))

        presenter.present(.firstRoutineCreated)

        #expect(presenter.pendingPlacement == nil)
    }

    // MARK: - Frequency cap

    @Test("A one-shot placement fires once, and the record survives a relaunch")
    func oneShotFiresOnce() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let presenter = makePresenter(defaults: defaults)
        raise(.firstRoutineCreated, on: presenter)

        #expect(presenter.pendingPlacement == .firstRoutineCreated)
        #expect(presenter.hasPresented(.firstRoutineCreated))

        presenter.dismiss()
        presenter.present(.firstRoutineCreated)

        #expect(presenter.pendingPlacement == nil)

        // A fresh presenter over the same defaults is what the next launch has.
        let relaunched = makePresenter(defaults: defaults)

        #expect(relaunched.hasPresented(.firstRoutineCreated))

        relaunched.present(.firstRoutineCreated)

        #expect(relaunched.pendingPlacement == nil)
    }

    @Test("The fired record is answered from state a view can observe")
    func firedRecordIsObservableState() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let presenter = makePresenter(defaults: defaults)

        raise(.valueMoment, on: presenter)

        // Writing the defaults behind the presenter's back must not change the
        // answer: the query reads the in-memory set, which is what makes a view
        // rendering "already fired" update without a relaunch.
        defaults.set(false, forKey: "pro.paywallPresented.value-moment")

        #expect(presenter.hasPresented(.valueMoment))
    }

    @Test("Contextual gates fire every time they are hit")
    func contextualGatesRepeat() {
        let presenter = makePresenter()

        raise(.routineCap, on: presenter)
        presenter.dismiss()
        raise(.routineCap, on: presenter)

        #expect(presenter.pendingPlacement == .routineCap)
        #expect(presenter.hasPresented(.routineCap) == false)
    }

    @Test("The debug reset lets a one-shot fire again")
    func resetRestoresOneShots() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let presenter = makePresenter(defaults: defaults)

        raise(.valueMoment, on: presenter)
        presenter.dismiss()
        presenter.resetPresentedPlacements()

        #expect(presenter.hasPresented(.valueMoment) == false)

        presenter.present(.valueMoment)

        #expect(presenter.pendingPlacement == .valueMoment)
    }

    // MARK: - Presentation state

    @Test("A second request does not swap the sheet already on screen")
    func doesNotReplaceAPresentedPaywall() {
        let presenter = makePresenter()

        raise(.routineCap, on: presenter)
        presenter.present(.chartMetric)

        #expect(presenter.pendingPlacement == .routineCap)
    }

    @Test("Dismissing clears the pending placement")
    func dismissClears() {
        let presenter = makePresenter()

        raise(.chartWindow, on: presenter)
        presenter.dismiss()

        #expect(presenter.pendingPlacement == nil)
    }

    @Test("After a dismissal the next placement presents again")
    func presentsAgainAfterDismissal() {
        let presenter = makePresenter()

        raise(.routineCap, on: presenter)
        presenter.dismiss()
        raise(.chartMetric, on: presenter)

        #expect(presenter.pendingPlacement == .chartMetric)
    }

    // MARK: - Helpers

    /// What the host does: raise the placement, and report it on screen if it
    /// landed. Tests that deliberately skip the second half are modelling a
    /// paywall the app root could not show.
    private func raise(_ placement: PaywallPlacement, on presenter: PaywallPresenter) {
        presenter.present(placement)
        if presenter.pendingPlacement == placement {
            presenter.didPresent(placement)
        }
    }

    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "PaywallPresentationTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    /// Defaults to gating **on**, unlike the shipped app: the eligibility logic
    /// is what these tests are about, and with the real `ProGating.isEnabled`
    /// they would all pass for the wrong reason.
    private func makePresenter(
        entitlements: StubEntitlements = StubEntitlements(state: .free),
        activeWorkout: StubActiveWorkout = StubActiveWorkout(),
        isGatingEnabled: Bool = true,
        defaults: UserDefaults? = nil
    ) -> PaywallPresenter {
        let suite = defaults ?? makeDefaults().defaults
        return PaywallPresenter(
            entitlements: entitlements,
            activeWorkout: activeWorkout,
            isGatingEnabled: isGatingEnabled,
            defaults: suite
        )
    }
}

// MARK: - Stubs

@MainActor
private final class StubEntitlements: ProEntitlementProviding {
    private(set) var state: ProEntitlementState

    init(state: ProEntitlementState) {
        self.state = state
    }

    var isPro: Bool { state.isPro }

    func refresh() async {}
}

@MainActor
private final class StubActiveWorkout: ActiveWorkoutReporting {
    private(set) var isWorkoutActive = false

    func setWorkoutActive(_ isActive: Bool) {
        isWorkoutActive = isActive
    }
}
