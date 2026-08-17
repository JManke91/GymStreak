//
//  PaywallPresenting.swift
//  GymStreak
//
//  How anything in the app asks for a paywall without knowing what a paywall
//  looks like or who renders it. See docs/pro-subscription.md.
//

import Foundation

/// Raises the paywall for a named placement.
///
/// A gate calls `present(.routineCap)` and is done: it never learns whether a
/// paywall appeared, what it looked like, or who drew it. That is deliberate —
/// the eligibility rules (the kill switch, the entitlement, §8's frequency cap
/// and Rule 3's absolute prohibition inside a workout) live in the conformer,
/// not spread across nine call sites.
///
/// `@MainActor` because presentation is UI, and every caller is already a
/// `@MainActor` ViewModel or View. Imports nothing beyond Foundation on purpose:
/// no SwiftUI, no StoreKit and no RevenueCat type may appear in this signature —
/// ticket 14 swaps the placeholder sheet for a RevenueCat paywall without a
/// caller changing.
@MainActor
protocol PaywallPresenting: AnyObject {

    /// The placement currently asking to be shown, or `nil`. The host near the
    /// app root renders this; nothing else should read it.
    var pendingPlacement: PaywallPlacement? { get }

    /// Requests the paywall for `placement`. Silently does nothing when the
    /// request is not eligible — a gate has no decision to make about that.
    func present(_ placement: PaywallPlacement)

    /// Reported by the host when its sheet reached the screen.
    ///
    /// A raised placement is not the same as a presented one: the app root also
    /// hosts full-screen covers (the coach chat, the AI opt-in), and a sheet
    /// raised while one of those is up never reaches the screen. This is what
    /// tells the presenter not to swap the contents of a paywall the user is
    /// looking at.
    func sheetDidAppear()

    /// Reported by the host when a **paywall** — an actual offer — is on screen.
    ///
    /// Separate from `sheetDidAppear()` because the sheet appears first and may
    /// never get further: resolving the offering is a network call, and it can
    /// end in "couldn't be loaded" (docs/pro-subscription.md §5j). Recording the
    /// §8 once-ever fire here is what stops a placement from being spent on a
    /// sheet that showed no offer — or on one nobody saw at all.
    func didPresent(_ placement: PaywallPlacement)

    /// Clears `pendingPlacement`. Called by the host when its sheet is dismissed.
    func dismiss()

    /// Whether a one-shot placement (§8 A and B) has already been shown on this
    /// install. Persists across launches; always `false` for contextual gates,
    /// which are not recorded.
    func hasPresented(_ placement: PaywallPlacement) -> Bool
}

#if DEBUG
/// Debug-only presentation surface behind the Settings debug section.
///
/// Separate from `PaywallPresenting` for the same reason `ProEntitlementDebugging`
/// is separate: the shipping protocol stays the narrow thing gates call. The
/// debug half exists because with `ProGating.isEnabled` off — which is how the
/// app shipped until ticket 15 — the ordinary `present(_:)` is inert by design,
/// so nothing would ever draw a paywall during development. It stays useful
/// after the flip: `present(_:)` now honours real eligibility, so a spent
/// one-shot or an entitled account still draws nothing.
@MainActor
protocol PaywallPresentationDebugging: PaywallPresenting {

    /// Raises `placement` ignoring the kill switch, the entitlement, and whether
    /// a one-shot already fired. **Rule 3 still holds**: it will not present
    /// during an active workout session, because that prohibition is absolute
    /// and a debug bypass of it would prove the wrong thing.
    func presentIgnoringEligibility(_ placement: PaywallPlacement)

    /// Forgets every recorded one-shot fire, so A and B can be tried again.
    func resetPresentedPlacements()
}
#endif
