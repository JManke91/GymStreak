//
//  LegalLinks.swift
//  GymStreak
//
//  The two legal documents App Review requires an app selling subscriptions to
//  link to. See docs/pro-subscription.md §5k.
//

import Foundation

/// Terms of Use and privacy policy, as URLs.
///
/// **These are a submission requirement, not a nicety.** Guideline 3.1.2(c)
/// requires an app offering auto-renewing subscriptions to carry a functional
/// link to both *inside the app*; version 1.1.9 shipped with neither and was
/// rejected for it on 2026-08-18. They are linked from two places, deliberately:
/// the RevenueCat paywall footer (dashboard-authored, so it can be fixed without
/// a release) and the Settings screen (in the binary, so it holds even if the
/// paywall never loads).
enum LegalLinks {

    /// Apple's standard End User Licence Agreement.
    ///
    /// Used instead of custom terms because Apple accepts it by definition —
    /// it is the agreement that applies to every app that does not supply its
    /// own. The App Description carries the same link, which is the metadata
    /// half of the same requirement.
    static let termsOfUse = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    )

    /// Gym Streak's privacy policy. Also the URL in App Store Connect's
    /// Privacy Policy field — the two must not drift apart.
    static let privacyPolicy = URL(
        string: "https://gist.github.com/JManke91/94e72298dd0de546c1f7718778661b58"
    )
}
