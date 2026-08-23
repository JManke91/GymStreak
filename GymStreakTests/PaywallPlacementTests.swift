//
//  PaywallPlacementTests.swift
//  GymStreakTests
//
//  The placement taxonomy itself — that every docs/monetization-strategy.md §8
//  trigger has a case, and that each carries what a headline needs. Split from
//  `PaywallPresentationTests`, which is about the presenter's eligibility rules.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
@MainActor
struct PaywallPlacementTests {

    @Test("Every §8 trigger has a placement, and each carries a headline key")
    func placementsCoverStrategy() {
        // Nine §8 triggers plus `settingsUpgrade`, which is not a §8 trigger at
        // all — it is the Settings purchase entry point added after App Review
        // could find no way to buy (appstore-rejection-1.1.9.md §3.9).
        #expect(PaywallPlacement.allCases.count == 10)

        for placement in PaywallPlacement.allCases {
            #expect(placement.identifier == placement.rawValue)
            #expect(placement.headlineKey.hasPrefix("paywall.headline."))
            // A missing entry in Localizable.strings resolves to the key itself.
            #expect(placement.headlineKey.localized != placement.headlineKey)
        }
    }

    @Test("Only placements A and B are once-ever")
    func oneShotPlacements() {
        let oneShot = PaywallPlacement.allCases.filter(\.isOneShot)

        #expect(Set(oneShot) == [.firstRoutineCreated, .valueMoment])
        #expect(PaywallPlacement.routineCap.kind == .contextualGate)
        // The Settings entry point must be re-openable: a user who dismisses the
        // paywall and comes back has to find it again.
        #expect(PaywallPlacement.settingsUpgrade.kind == .contextualGate)
        #expect(!PaywallPlacement.settingsUpgrade.isOneShot)
    }
}
