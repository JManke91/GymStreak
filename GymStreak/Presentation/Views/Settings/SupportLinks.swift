//
//  SupportLinks.swift
//  GymStreak
//
//  Outbound links of the Settings tab's Support section. See docs/settings-tab.md.
//

import Foundation

/// Static destinations the Support section links to.
enum SupportLinks {

    /// Gym Streak's App Store Apple ID (App Store Connect → App Information → General).
    static let appStoreAppID = "6756426105"

    /// Deep link to the App Store's write-a-review composer.
    ///
    /// A universal link, so on device it opens the App Store app directly on the
    /// review sheet instead of bouncing through Safari. Deliberately used instead
    /// of `requestReview()`, which Apple documents as unsuitable for a button tap.
    /// The app *does* call `requestReview()` — automatically, never from a
    /// control (`ReviewPromptCoordinator`, docs/rating-prompt.md); this row is
    /// the path for a user who wants to write one on their own initiative.
    static let writeReview = URL(
        string: "https://apps.apple.com/app/id\(appStoreAppID)?action=write-review"
    )

    /// App Store Connect provider token, the `pt` of a campaign link (App Store Connect →
    /// Analytics → Campaigns). Without it a `ct` is not attributed, so neither is sent.
    // TODO(share-screen): paste the provider token here once known. The link then becomes
    // https://apps.apple.com/app/apple-store/id6756426105?pt=<token>&ct=<campaign>&mt=8
    static let appStoreProviderToken: String? = nil

    /// The App Store page with campaign attribution, for links that leave the app inside
    /// shared content (docs/workout-sharing.md). The only place such a link is built.
    static func appStoreCampaignLink(campaign: String) -> URL {
        guard let token = appStoreProviderToken else {
            return URL(string: "https://apps.apple.com/app/id\(appStoreAppID)")!
        }
        var components = URLComponents(string: "https://apps.apple.com/app/apple-store/id\(appStoreAppID)")!
        components.queryItems = [
            URLQueryItem(name: "pt", value: token),
            URLQueryItem(name: "ct", value: campaign),
            URLQueryItem(name: "mt", value: "8")
        ]
        return components.url!
    }

    /// Campaign names, one per place a link is shared from.
    enum Campaign {
        static let shareSummary = "share-summary"
    }

    /// Where "Contact support" addresses its mail. Also the address shown in the
    /// fallback alert when no mail client accepts the `mailto:` URL.
    static let supportEmail = "julian.manke@googlemail.com"
}

/// The app's name as it appears inside shared content. One constant, so a rename changes a
/// single place (docs/acquisition-strategy.md, lever #15).
enum AppBrand {
    static let wordmark = "GymStreak"
}
