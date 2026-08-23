//
//  SubscriptionStatusTests.swift
//  GymStreakTests
//
//  The Settings subscription section's copy mapping (docs/pro-subscription.md §5i).
//
//  Three things carry the ticket: the section is **absent entirely** while the
//  gating kill switch is off, every entitlement is described by its **own**
//  copy — a Founder must never be told they hold a subscription, and a lifetime
//  buyer must never be told something renews — and every key the section
//  renders actually resolves in both shipped languages.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
@MainActor
struct SubscriptionStatusTests {

    // MARK: - The kill switch

    @Test(
        "With gating off there is no subscription section at all",
        arguments: ProEntitlementState.allCases
    )
    func killSwitchOffShowsNothing(state: ProEntitlementState) {
        #expect(SubscriptionStatusSummary(state: state, isGatingEnabled: false) == nil)
    }

    @Test("With gating on every entitlement is described")
    func gatingOnDescribesEveryState() {
        for state in ProEntitlementState.allCases {
            #expect(SubscriptionStatusSummary(state: state, isGatingEnabled: true) != nil)
        }
    }

    // MARK: - Each source is reported as itself

    @Test(
        "The plan reported is the entitlement's own source",
        arguments: zip(
            ProEntitlementState.allCases,
            [
                SubscriptionStatusSummary.Plan.free,
                .founder,
                .subscription,
                .lifetime
            ]
        )
    )
    func planFollowsTheEntitlementSource(
        state: ProEntitlementState,
        expected: SubscriptionStatusSummary.Plan
    ) {
        #expect(SubscriptionStatusSummary(state: state, isGatingEnabled: true)?.plan == expected)
    }

    @Test("A Founder is reported as a Founder, and as Pro")
    func founderIsStatedPlainly() {
        let summary = SubscriptionStatusSummary(state: .founder, isGatingEnabled: true)
        #expect(summary?.plan == .founder)
        #expect(summary?.isPro == true)
        // The Founder grant is not a subscription, and saying so would be a
        // factual error about the user's own money.
        #expect(summary?.titleKey != SubscriptionStatusSummary(
            state: .subscription,
            isGatingEnabled: true
        )?.titleKey)
    }

    @Test("Only the free tier is reported as not Pro")
    func onlyFreeIsNotPro() {
        for state in ProEntitlementState.allCases {
            let summary = SubscriptionStatusSummary(state: state, isGatingEnabled: true)
            #expect(summary?.isPro == state.isPro)
        }
    }

    /// A copy-paste in the key switches would silently collapse two plans into
    /// one description — which is exactly the class of bug that would tell a
    /// lifetime buyer their purchase renews.
    @Test("No two plans share a description")
    func everyPlanHasItsOwnCopy() {
        let details = Set(
            ProEntitlementState.allCases.compactMap {
                SubscriptionStatusSummary(state: $0, isGatingEnabled: true)?.detailKey
            }
        )
        #expect(details.count == ProEntitlementState.allCases.count)

        let footers = Set(
            ProEntitlementState.allCases.compactMap {
                SubscriptionStatusSummary(state: $0, isGatingEnabled: true)?.footerKey
            }
        )
        #expect(footers.count == ProEntitlementState.allCases.count)
    }

    // MARK: - What each tier is offered

    /// The Customer Center is for people with something to manage. Offering it
    /// to a free user is what produced the "No subscriptions found" screen App
    /// Review screenshotted (appstore-rejection-1.1.9.md §3.7).
    @Test("Only entitled, non-Founder plans are offered the Customer Center")
    func customerCenterIsOfferedToPayingPlansOnly() {
        for state in ProEntitlementState.allCases {
            let summary = SubscriptionStatusSummary(state: state, isGatingEnabled: true)
            #expect(summary?.showsCustomerCenter == (state == .subscription || state == .lifetime))
        }
    }

    /// A Founder is not a RevenueCat customer at all (§9.3): the Customer Center
    /// would open on empty purchase history and offer to restore a purchase that
    /// never existed.
    @Test("A Founder is offered nothing to manage")
    func founderIsOfferedNoCustomerCenter() {
        let summary = SubscriptionStatusSummary(state: .founder, isGatingEnabled: true)
        #expect(summary?.showsCustomerCenter == false)
    }

    /// The two rejection fixes: a free user must be able to buy, and — Guideline
    /// 3.1.1 — to restore, without the app first believing they paid.
    @Test("Only a free user is offered the upgrade and restore rows")
    func freeTierIsOfferedUpgradeAndRestore() {
        for state in ProEntitlementState.allCases {
            let summary = SubscriptionStatusSummary(state: state, isGatingEnabled: true)
            #expect(summary?.showsUpgradeAction == (state == .free))
            #expect(summary?.showsRestoreAction == (state == .free))
        }
    }

    /// Every tier must offer *something*, or Settings has another dead end.
    @Test("No tier is left with a status row and nothing to do")
    func everyTierHasAnActionExceptFounder() {
        for state in ProEntitlementState.allCases where state != .founder {
            let summary = SubscriptionStatusSummary(state: state, isGatingEnabled: true)
            let hasAction = (summary?.showsUpgradeAction ?? false)
                || (summary?.showsRestoreAction ?? false)
                || (summary?.showsCustomerCenter ?? false)
            #expect(hasAction, "\(state) has no action in the subscription section")
        }
    }

    @Test("The free tier's upgrade and restore copy resolves in en and de")
    func freeTierCopyResolves() throws {
        for language in ["en", "de"] {
            let bundle = try #require(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
            )
            for key in [
                "settings.subscription.upgrade.title",
                "settings.subscription.upgrade.subtitle",
                "settings.subscription.restore.title",
                "settings.subscription.restore.subtitle",
                "settings.subscription.restore.subtitle.running",
                "settings.subscription.restore.restored.title",
                "settings.subscription.restore.restored.message",
                "settings.subscription.restore.none.title",
                "settings.subscription.restore.none.message",
                "settings.subscription.restore.failed.title",
                "settings.subscription.restore.failed.message",
                "common.ok",
            ] {
                #expect(bundle.localizedString(forKey: key, value: nil, table: nil) != key)
            }
        }
    }

    @Test("The Customer Center row's copy resolves in en and de")
    func customerCenterCopyResolves() throws {
        for language in ["en", "de"] {
            let bundle = try #require(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
            )
            for key in [
                "settings.subscription.manage.title",
                "settings.subscription.manage.subtitle"
            ] {
                let value = bundle.localizedString(forKey: key, value: nil, table: nil)
                #expect(value != key, "\(key) is missing from \(language).lproj")
            }
        }
    }

    // MARK: - The strings exist

    @Test(
        "Every string the section renders resolves in en and de",
        arguments: ProEntitlementState.allCases
    )
    func everyStringResolves(state: ProEntitlementState) throws {
        let summary = try #require(
            SubscriptionStatusSummary(state: state, isGatingEnabled: true)
        )
        for language in ["en", "de"] {
            let bundle = try #require(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
            )
            for key in [summary.titleKey, summary.detailKey, summary.footerKey] {
                let value = bundle.localizedString(forKey: key, value: nil, table: nil)
                #expect(value != key, "\(key) is missing from \(language).lproj")
            }
        }
    }

    @Test("The section header resolves in en and de")
    func headerResolves() throws {
        for language in ["en", "de"] {
            let bundle = try #require(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
            )
            let key = "settings.section.subscription"
            #expect(bundle.localizedString(forKey: key, value: nil, table: nil) != key)
        }
    }
}
