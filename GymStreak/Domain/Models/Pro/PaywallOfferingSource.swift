//
//  PaywallOfferingSource.swift
//  GymStreak
//
//  Which offering a raised placement ended up showing — and what happens when
//  there is none. See docs/pro-subscription.md §5j.
//

import Foundation

/// The outcome of resolving a `PaywallPlacement` to a RevenueCat offering.
///
/// The ladder itself is three lines of logic, and it lives here rather than
/// inside the paywall view for one reason: **the failure rung is the one that
/// must not regress.** A placement not configured in the dashboard, an offline
/// launch, or a renamed case (`rawValue` is a wire string — §5a) all end at the
/// same place, and "what does the user see then" is a product decision, not an
/// implementation detail of a `View`. A `View` cannot be asserted against; this
/// can.
///
/// No RevenueCat type appears here, so `Domain/` stays free of the SDK: the
/// caller passes in two booleans it already knows.
enum PaywallOfferingSource: Equatable, Sendable {

    /// The dashboard served an offering for this placement's identifier — the
    /// case the whole placement indirection exists for.
    case placement

    /// No placement offering, but the project has a current (default) offering.
    /// The user still gets a real paywall; only the per-placement copy is lost.
    case defaultOffering

    /// Nothing could be resolved. The gate stays closed and the sheet says so —
    /// see `resolve(hasPlacementOffering:hasDefaultOffering:)`.
    case unavailable

    /// Picks the rung, given what the SDK returned.
    ///
    /// **`unavailable` never unlocks the gated capability.** The alternative —
    /// letting the action through when offerings fail to load — turns airplane
    /// mode into a one-tap bypass of every gate in the app, so it is not on the
    /// table. What the user loses instead is nothing they had: every gate in
    /// §5c–§5f is additive (a fourth routine, a wider chart window, one more AI
    /// call), so a paywall that cannot load leaves the free tier exactly as it
    /// was. The sheet is honest about it and offers a retry rather than showing
    /// an empty surface.
    static func resolve(
        hasPlacementOffering: Bool,
        hasDefaultOffering: Bool
    ) -> PaywallOfferingSource {
        if hasPlacementOffering { return .placement }
        if hasDefaultOffering { return .defaultOffering }
        return .unavailable
    }

    /// Short label for the log line that records which rung was taken. Worth
    /// having: a placement silently falling back to the default offering is
    /// invisible on screen and is exactly what a dashboard typo produces.
    var logLabel: String {
        switch self {
        case .placement: "placement"
        case .defaultOffering: "default-offering-fallback"
        case .unavailable: "unavailable"
        }
    }
}
