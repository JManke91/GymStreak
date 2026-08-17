//
//  ProGatingTestDoubles.swift
//  GymStreakTests
//
//  Shared doubles for the Pro gate tickets (06–11): a fixed entitlement and a
//  paywall seam that records what a gate asked for instead of presenting it.
//  `PaywallPresentationTests` keeps its own private stubs — it is testing the
//  real presenter, not standing in for one.
//

import Foundation
@testable import GymStreak

/// A `ProEntitlementProviding` pinned to one state.
@MainActor
final class StubProEntitlements: ProEntitlementProviding {

    var state: ProEntitlementState

    init(state: ProEntitlementState = .free) {
        self.state = state
    }

    var isPro: Bool { state.isPro }

    func refresh() async {}
}

/// Records every placement a gate raised. Presents nothing — the eligibility
/// rules belong to `PaywallPresenter`, and a gate's job is only to ask.
@MainActor
final class RecordingPaywallPresenter: PaywallPresenting {

    private(set) var presentedPlacements: [PaywallPlacement] = []
    private(set) var pendingPlacement: PaywallPlacement?

    func present(_ placement: PaywallPlacement) {
        presentedPlacements.append(placement)
        pendingPlacement = placement
    }

    func sheetDidAppear() {}

    func didPresent(_ placement: PaywallPlacement) {}

    func dismiss() {
        pendingPlacement = nil
    }

    func hasPresented(_ placement: PaywallPlacement) -> Bool {
        presentedPlacements.contains(placement)
    }

    /// Forgets the recording, so a test can set up state through the gate and
    /// then assert only on what the step under test raised.
    func reset() {
        presentedPlacements.removeAll()
        pendingPlacement = nil
    }
}

/// An `AICoachAvailabilityProviding` pinned to one state, mutable so a test can
/// move the device in and out of Apple-Intelligence availability.
///
/// The AI taster gates (tickets 08/09) check availability *before* the
/// entitlement — an ineligible device must never be paywalled — so every one of
/// those tests needs to drive this.
@MainActor
final class StubAICoachAvailability: AICoachAvailabilityProviding {

    var state: AICoachAvailabilityState

    init(state: AICoachAvailabilityState = .available) {
        self.state = state
    }

    var isAvailable: Bool { state == .available }

    func refresh() async {}
}
