//
//  SupportLinksCampaignTests.swift
//  GymStreakTests
//
//  The attributed App Store link every share card carries. See docs/workout-sharing.md.
//

import Foundation
import Testing
@testable import GymStreak

struct SupportLinksCampaignTests {

    @Test(arguments: [
        SupportLinks.Campaign.shareSummary,
        SupportLinks.Campaign.shareHistory,
        SupportLinks.Campaign.shareConditioning
    ])
    func campaignLinkMatchesAppStoreConnectFormat(campaign: String) {
        #expect(SupportLinks.appStoreCampaignLink(campaign: campaign).absoluteString
            == "https://apps.apple.com/app/apple-store/id6756426105?pt=122361031&ct=\(campaign)&mt=8")
    }
}
