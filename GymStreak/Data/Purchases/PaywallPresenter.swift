//
//  PaywallPresenter.swift
//  GymStreak
//
//  The one place that decides whether a paywall request becomes a paywall.
//  Ticket 14 replaces what it *shows*, not what it decides.
//  See docs/pro-subscription.md.
//

import Foundation
import Observation

/// Turns a placement request into a presented paywall — or, more often, into
/// nothing at all.
///
/// Every eligibility rule lives here rather than at the gates:
///
/// 1. **The kill switch.** With `ProGating.isEnabled` off the app must behave
///    exactly as it did before monetization, and "no gate blocks but a paywall
///    still appears" is not that.
/// 2. **Rule 3 (absolute).** No paywall, upsell or Pro badge inside an active
///    workout session (`monetization-strategy.md` §8). Enforced from the single
///    app-wide workout flag instead of trusting nine call sites to remember —
///    the failure mode is a rage-uninstall.
/// 3. **The entitlement.** A Pro user — including a Founder — is never shown a
///    paywall, whatever a gate thinks.
/// 4. **§8's frequency cap.** Placements A and B fire once each, ever.
///
/// `@Observable` + `@MainActor` like the entitlement provider: `pendingPlacement`
/// is read directly by the host near the app root, so a request anywhere raises
/// the sheet with no further plumbing.
@Observable
@MainActor
final class PaywallPresenter: PaywallPresenting {

    private(set) var pendingPlacement: PaywallPlacement?

    /// Whether the host's sheet actually reached the screen. A raised
    /// placement is not a presented one — the app root also hosts full-screen
    /// covers, and a sheet raised while one is up never appears.
    ///
    /// Set by `sheetDidAppear()` rather than by `didPresent(_:)`: the paywall
    /// inside the sheet resolves its offering over the network and may never get
    /// as far as an offer, and the user is looking at *the sheet* the whole time
    /// — including while it loads and if it ends in "couldn't be loaded". Tying
    /// this to the offer would let a request landing during that window swap the
    /// sheet out from under them.
    private var isPresented = false

    /// The one-shot placements already shown on this install.
    ///
    /// Held in memory *as well as* in `defaults` because `UserDefaults` is not
    /// observable: `hasPresented(_:)` reading it directly meant a view rendering
    /// from the answer (the debug section's "already fired") only picked up a
    /// change on the next launch. Reading this stored property is what SwiftUI
    /// can track. Seeded from `defaults` at init, which is what makes the record
    /// survive a relaunch.
    private var presentedOneShots: Set<PaywallPlacement> = []

    private let entitlements: any ProEntitlementProviding
    private let activeWorkout: any ActiveWorkoutReporting
    private let isGatingEnabled: Bool
    private let defaults: UserDefaults

    /// - Parameters:
    ///   - isGatingEnabled: injected rather than read from `ProGating` inside
    ///     `present(_:)` so the eligibility logic is testable while the shipped
    ///     switch is off — with the flag baked in, every test would have to go
    ///     through the debug bypass and would stop proving the shipping path.
    ///   - defaults: `UserDefaults.standard`, not the App Group suite. The
    ///     one-shot record is device-local presentation history, nothing the
    ///     widget or the watch can use, and it is deliberately *not* mirrored to
    ///     iCloud — a reinstall showing the soft placement A once more is the
    ///     benign outcome.
    init(
        entitlements: any ProEntitlementProviding,
        activeWorkout: any ActiveWorkoutReporting,
        isGatingEnabled: Bool = ProGating.isEnabled,
        defaults: UserDefaults = .standard
    ) {
        self.entitlements = entitlements
        self.activeWorkout = activeWorkout
        self.isGatingEnabled = isGatingEnabled
        self.defaults = defaults
        self.presentedOneShots = Set(
            PaywallPlacement.allCases.filter {
                $0.isOneShot && defaults.bool(forKey: Self.presentedKey($0))
            }
        )
    }

    func present(_ placement: PaywallPlacement) {
        guard isGatingEnabled else { return }
        guard !entitlements.isPro else { return }
        guard !(placement.isOneShot && hasPresented(placement)) else { return }
        show(placement)
    }

    func sheetDidAppear() {
        isPresented = true
    }

    func didPresent(_ placement: PaywallPlacement) {
        // Spent only once an offer is on the screen — a placement that was
        // raised but never appeared (something was covering the app root), or
        // one whose offering could not be resolved, stays available.
        if placement.isOneShot {
            presentedOneShots.insert(placement)
            defaults.set(true, forKey: Self.presentedKey(placement))
        }
    }

    func dismiss() {
        pendingPlacement = nil
        isPresented = false
    }

    func hasPresented(_ placement: PaywallPlacement) -> Bool {
        presentedOneShots.contains(placement)
    }

    /// The half of presentation that no caller may bypass.
    private func show(_ placement: PaywallPlacement) {
        guard !activeWorkout.isWorkoutActive else { return }
        // Never swap the contents of a paywall the user is looking at. A
        // placement that was raised but never appeared is replaced instead —
        // otherwise one request the app root could not show (a full-screen
        // cover was up) would wedge the seam for the rest of the session.
        guard !isPresented else { return }

        pendingPlacement = placement
    }

    /// Keyed by the placement identifier, so the record survives reordering the
    /// enum and follows a case rename the same way the dashboard Placement does.
    private static func presentedKey(_ placement: PaywallPlacement) -> String {
        "pro.paywallPresented.\(placement.identifier)"
    }
}

#if DEBUG
extension PaywallPresenter: PaywallPresentationDebugging {

    func presentIgnoringEligibility(_ placement: PaywallPlacement) {
        show(placement)
    }

    func resetPresentedPlacements() {
        presentedOneShots.removeAll()
        for placement in PaywallPlacement.allCases where placement.isOneShot {
            defaults.removeObject(forKey: Self.presentedKey(placement))
        }
    }
}
#endif
