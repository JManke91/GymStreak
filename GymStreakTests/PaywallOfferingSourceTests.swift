//
//  PaywallOfferingSourceTests.swift
//  GymStreakTests
//
//  The fallback ladder a raised placement walks down when the dashboard does
//  not have what it asked for (docs/pro-subscription.md §5j).
//
//  This is the half of the paywall swap that has no visible happy path: a
//  placement missing from the dashboard, a renamed case (`rawValue` is a wire
//  string) and an offline launch all land here, and none of them errors. The
//  ladder is asserted rather than eyeballed for exactly that reason.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
@MainActor
struct PaywallOfferingSourceTests {

    @Test("A placement offering is preferred over the default one")
    func placementWins() {
        #expect(
            PaywallOfferingSource.resolve(
                hasPlacementOffering: true,
                hasDefaultOffering: true
            ) == .placement
        )
        // The placement offering alone is enough — the project having no
        // "current" offering is not a reason to ignore a configured placement.
        #expect(
            PaywallOfferingSource.resolve(
                hasPlacementOffering: true,
                hasDefaultOffering: false
            ) == .placement
        )
    }

    /// The silent case: a Placement that was never created in the dashboard, or
    /// a case renamed on this side only. The user still gets a real paywall.
    @Test("Without a placement offering the default offering is used")
    func defaultOfferingIsTheFallback() {
        #expect(
            PaywallOfferingSource.resolve(
                hasPlacementOffering: false,
                hasDefaultOffering: true
            ) == .defaultOffering
        )
    }

    @Test("With nothing to show the paywall is unavailable, not empty")
    func nothingResolvesToUnavailable() {
        #expect(
            PaywallOfferingSource.resolve(
                hasPlacementOffering: false,
                hasDefaultOffering: false
            ) == .unavailable
        )
    }

    /// Each rung has to be distinguishable in a log, because a placement quietly
    /// falling back to the default offering looks identical on screen to one
    /// that worked.
    @Test("Every rung logs as itself")
    func logLabelsAreDistinct() {
        let labels = Set(
            [PaywallOfferingSource.placement, .defaultOffering, .unavailable].map(\.logLabel)
        )
        #expect(labels.count == 3)
    }

    // MARK: - The strings the unavailable state renders

    @Test("The unavailable state's copy resolves in en and de")
    func unavailableCopyResolves() throws {
        for language in ["en", "de"] {
            let bundle = try #require(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
            )
            for key in ["paywall.unavailable.body", "action.retry", "action.dismiss"] {
                let value = bundle.localizedString(forKey: key, value: nil, table: nil)
                #expect(value != key, "\(key) is missing from \(language).lproj")
            }
        }
    }
}
