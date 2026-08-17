//
//  FounderCelebrationCoordinator.swift
//  GymStreak
//
//  When the Founder thank-you screen is due, and when it is safe to show it.
//  See docs/pro-subscription.md §5h.
//

import Foundation
import Observation

/// Decides whether the one-time "you're a Founder, Pro is yours" screen should
/// be on screen right now.
///
/// It is the counterpart to `PaywallPresenter` for the one screen that is not a
/// paywall: same shape (an observable flag the app root renders from, every
/// eligibility rule in one place), opposite content — it sells nothing, and it
/// exists precisely so a grandfathered user meets the good news before anything
/// that looks like bad news (`monetization-strategy.md` §7).
///
/// Four rules, all of them here rather than at the host:
///
/// 1. **The kill switch.** With `ProGating.isEnabled` off nothing in the app is
///    gated, so there is nothing to reassure anyone about — and showing the
///    screen early would *spend* it, leaving the release that actually turns
///    gating on with nobody left to thank. This is the rule that makes the
///    screen arrive on the launch of the build that flips the switch.
/// 2. **The entitlement source.** Only `.founder`. A subscriber, a free user and
///    — critically — a user whose Founder decision is still **undecided** all
///    see nothing. The undecided case falls out of the entitlement itself:
///    `FounderStatusService` leaves the decision absent on a first-launch
///    offline, so the provider reports `.free` and re-resolves next launch. That
///    is the intended behaviour: telling someone they are a Founder and taking
///    it back is worse than telling them a launch late.
/// 3. **Rule 3.** Nothing about Pro inside an active workout session
///    (`monetization-strategy.md` §8). Deferred, never dropped — the record is
///    only written on dismissal, so a suppressed screen is still owed.
/// 4. **Once, ever**, via `FounderCelebrationTracking`.
///
/// `@Observable` + `@MainActor`, and held concretely by the app root: the host
/// binds a `.fullScreenCover` to `isPresenting`, so raising the screen from a
/// launch task needs no further plumbing.
@Observable
@MainActor
final class FounderCelebrationCoordinator {

    /// Whether the screen should be on screen. Written only by this type; the
    /// host reports the dismissal back through `celebrationWasDismissed()`.
    private(set) var isPresenting = false

    /// Whether the user has already been thanked.
    ///
    /// Mirrored into observable storage from `record` — which is a plain
    /// `UserDefaults`-backed store and therefore not observable — for the same
    /// reason `PaywallPresenter` keeps its fired set in memory: a view that
    /// renders from the answer (the debug section's "already shown") would
    /// otherwise only pick up a change on the next launch. Seeded at init, which
    /// is what makes the record survive a relaunch.
    private(set) var hasCelebrated: Bool

    private let entitlements: any ProEntitlementProviding
    private let record: any FounderCelebrationTracking
    private let activeWorkout: any ActiveWorkoutReporting
    private let isGatingEnabled: Bool

    /// - Parameter isGatingEnabled: injected rather than read from `ProGating`
    ///   inside the check, for the same reason `PaywallPresenter` injects it:
    ///   with the shipped switch baked in, every test would pass by proving the
    ///   screen is inert rather than that it is correct.
    init(
        entitlements: any ProEntitlementProviding,
        record: any FounderCelebrationTracking,
        activeWorkout: any ActiveWorkoutReporting,
        isGatingEnabled: Bool = ProGating.isEnabled
    ) {
        self.entitlements = entitlements
        self.record = record
        self.activeWorkout = activeWorkout
        self.isGatingEnabled = isGatingEnabled
        self.hasCelebrated = record.hasCelebrated
    }

    /// Raises the screen if this user is a Founder who has not been thanked yet
    /// and the moment is a safe one.
    ///
    /// Called at two deterministic moments rather than observed into existence:
    /// right after the launch `refresh()` that resolves the grant (so the very
    /// first launch of the gating build shows it), and on every foreground (so a
    /// screen Rule 3 suppressed arrives at the next safe moment instead of
    /// waiting for a relaunch). Both are idempotent.
    func presentIfDue() {
        guard !isPresenting, !hasCelebrated else { return }
        guard isGatingEnabled else { return }
        guard entitlements.state == .founder else { return }
        // Deferred, not consumed: nothing is written here, so the next
        // foreground or the next launch raises it again.
        guard !activeWorkout.isWorkoutActive else { return }
        isPresenting = true
    }

    /// Reported by the host when the screen has been dismissed.
    ///
    /// **This is where the once-ever is spent, not where it is raised** — the
    /// same distinction `PaywallPresenter` draws between a raised and a
    /// presented placement. A screen that never reached the user (the app was
    /// killed while it was up, or something else was covering the app root) is
    /// still owed, and the guard is what makes that true: a binding pushed to
    /// `false` while nothing is presenting records nothing.
    func celebrationWasDismissed() {
        guard isPresenting else { return }
        isPresenting = false
        hasCelebrated = true
        record.recordCelebrated()
    }

    #if DEBUG
    /// Raises the screen ignoring the kill switch, the entitlement and the
    /// once-ever record. **Rule 3 still holds** — bypassing the one prohibition
    /// that is absolute would prove the wrong thing.
    ///
    /// It exists because the Founder grant can never resolve outside a
    /// production App Store install (docs/pro-subscription.md §3a), so this and
    /// the debug entitlement picker are the only ways to see the screen at all
    /// during development.
    func presentIgnoringEligibility() {
        guard !activeWorkout.isWorkoutActive else { return }
        isPresenting = true
    }

    /// Forgets that the screen was shown — the record *and* the mirror, which is
    /// why the reset lives here rather than on the store.
    func resetCelebration() {
        hasCelebrated = false
        record.resetCelebration()
    }
    #endif
}
