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
    static let writeReview = URL(
        string: "https://apps.apple.com/app/id\(appStoreAppID)?action=write-review"
    )

    /// Where "Contact support" addresses its mail. Also the address shown in the
    /// fallback alert when no mail client accepts the `mailto:` URL.
    static let supportEmail = "julian.manke@googlemail.com"
}
