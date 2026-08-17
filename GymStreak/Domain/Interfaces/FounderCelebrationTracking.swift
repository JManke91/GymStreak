//
//  FounderCelebrationTracking.swift
//  GymStreak
//
//  Whether the Founder thank-you screen has already been shown on this install.
//  See docs/pro-subscription.md §5h.
//

import Foundation

/// The durable "the Founder celebration has been seen" record.
///
/// Its own protocol rather than a flag on `FounderStatusResolving`, because the
/// two answer different questions and change at different times: *is this user a
/// Founder* is resolved once from `AppTransaction` and is permanent, while *have
/// we thanked them yet* is device-local presentation history — the same
/// distinction `PaywallPresenter`'s once-ever record draws against the
/// entitlement it reads.
///
/// `@MainActor` like the rest of the Pro protocol surface, and it imports
/// nothing beyond Foundation on purpose: no `UserDefaults` key may appear in
/// this signature.
@MainActor
protocol FounderCelebrationTracking: AnyObject {

    /// Whether the screen has already been shown. Cheap by contract — it is
    /// asked on every launch and every foreground, so a conformer answers from
    /// memory rather than from I/O.
    var hasCelebrated: Bool { get }

    /// Records that the screen was shown and dismissed. Idempotent, one-way:
    /// nothing ever un-celebrates.
    func recordCelebrated()

    #if DEBUG
    /// Forgets that the screen was shown, so it can be raised again.
    ///
    /// A requirement inside `#if DEBUG` rather than a second `…Debugging`
    /// protocol (the shape `PaywallPresentationDebugging` takes) because
    /// `FounderCelebrationCoordinator` mirrors this flag into observable
    /// storage: a reset that did not go through the coordinator would clear the
    /// stored answer and leave the mirror saying "already shown". One protocol
    /// keeps the reset on the one type that can do it correctly.
    ///
    /// It exists because the Founder grant can never resolve outside a
    /// production App Store install (docs/pro-subscription.md §3a), and the
    /// screen is once-ever — so without a reset it could be seen exactly once
    /// per simulator, which is not enough to check it in dark mode, at
    /// accessibility type sizes and in both languages.
    func resetCelebration()
    #endif
}
