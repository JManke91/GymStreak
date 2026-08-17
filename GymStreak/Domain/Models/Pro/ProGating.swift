//
//  ProGating.swift
//  GymStreak
//
//  The single global switch that turns Pro gating on. Ships on since
//  ticket 15 (2026-08-17); it shipped off through Phase 1.
//  See docs/monetization-strategy.md §9 and docs/pro-subscription.md §9.4a.
//

import Foundation

/// Master switch for every Pro gate in the app.
///
/// One flag, not one per gate: §9's rollout ships the entitlement layer
/// silently (Phase 1) and flips gating on in a later release (Phase 2), so
/// every gate must be a no-op in the shipped app until that single flip. A
/// per-gate flag set would make "is gating live?" un-answerable at a glance and
/// allow a half-gated release.
///
/// A gate reads this *and* the entitlement — `ProGating.isEnabled` alone never
/// blocks anything, and with it `false` the app behaves exactly as it did
/// before monetization.
enum ProGating {

    /// What a shipping build does. `true` since the Phase 2 launch release
    /// (ticket 15, 2026-08-17) flipped it — this is the constant that flip
    /// changed, and flipping it back is the documented rollback (§9.6).
    ///
    /// Read `isEnabled`, not this, everywhere except the assertion that pins the
    /// shipped value.
    static let shippedValue = true

    /// Whether gating is live in *this* run.
    ///
    /// `shippedValue`, unless a Debug build was launched with one of the two
    /// override arguments. They exist because the alternative is worse:
    /// exercising the app in the state it is *not* currently shipping used to
    /// mean editing `shippedValue` and remembering not to commit it.
    ///
    /// Both directions are needed, and at different times.
    /// `-PRO_GATING_ON` mattered before the launch, when every gate, the
    /// paywall, the Settings subscription section and the Founder screen were
    /// inert. `-PRO_GATING_OFF` matters now that gating ships on: it is the only
    /// way to see the pre-monetization app again, which is exactly what
    /// verifying §9.6's rollback — no gate left behind in a degraded state, no
    /// data lost — requires.
    ///
    /// `-PRO_GATING_OFF` wins when both are passed. The precedence is arbitrary
    /// but has to be *some* order, and the safer default when a scheme has
    /// accumulated both is the one that blocks nothing.
    ///
    /// The scheme is shared and tracked, so ticking an argument *is* a diff —
    /// but a visible one-attribute diff in `GymStreak.xcscheme`, not a semantic
    /// change to Swift that reads as intentional. The guarantee that matters is
    /// that both arguments are `#if DEBUG`, so neither can affect a shipping
    /// build however they are left.
    ///
    /// A `static let`, so `ProcessInfo` is read once and the value cannot change
    /// under a gate mid-session — the flag is a launch property, not a setting.
    /// Reading `ProcessInfo` here does not compromise `Domain/`: it is neither
    /// persistence nor a Data type, and the alternative (injecting an effective
    /// flag from the composition root) would have to reach the eight call sites
    /// that take this as a default argument.
    static let isEnabled: Bool = {
        #if DEBUG
        if forceOffRequested {
            return false
        }
        if forceOnRequested {
            return true
        }
        #endif
        return shippedValue
    }()

    /// Where this run's value came from, in words, for the launch log.
    ///
    /// It exists because the two "gating is off" states look identical on screen
    /// *and* identical to a working Pro subscription — no cap nudge, no locks —
    /// so "it works after a restart" is not evidence of anything until you know
    /// which of the three you were looking at (docs/pro-subscription.md §9.4b).
    static var gatingSourceDescription: String {
        #if DEBUG
        if isForcedOffForDebugging {
            return "forced off by \(forceOffLaunchArgument)"
        }
        if isForcedOnForDebugging {
            return shippedValue
                ? "\(forceOnLaunchArgument) passed, but shippedValue is already on"
                : "forced on by \(forceOnLaunchArgument)"
        }
        return "shippedValue; neither \(forceOnLaunchArgument) nor \(forceOffLaunchArgument) "
            + "passed — Xcode scheme arguments are absent on a manual relaunch"
        #else
        return "shippedValue"
        #endif
    }

    #if DEBUG
    /// Add to the scheme under Run → Arguments → Arguments Passed On Launch.
    static let forceOnLaunchArgument = "-PRO_GATING_ON"

    /// The counterpart, and the one that matters after the launch flip: it puts
    /// a Debug run back into the pre-monetization app (§9.6's rollback check).
    static let forceOffLaunchArgument = "-PRO_GATING_OFF"

    /// Whether each argument was actually passed, read once from `ProcessInfo`.
    ///
    /// **Both predicates below derive from these, never from comparing
    /// `isEnabled` against `shippedValue`.** That comparison describes the
    /// *outcome*, and it goes silently vacuous whenever the argument agrees
    /// with the shipped value: with gating shipped on, `isEnabled && !shippedValue`
    /// is `false` even on a run that passed `-PRO_GATING_ON`, so the launch log
    /// would report "argument not passed" — which is exactly the wrong
    /// conclusion §9.4b's trap 1 exists to prevent.
    private static let forceOnRequested =
        ProcessInfo.processInfo.arguments.contains(forceOnLaunchArgument)

    private static let forceOffRequested =
        ProcessInfo.processInfo.arguments.contains(forceOffLaunchArgument)

    /// `true` when `-PRO_GATING_ON` decided this run — it was passed and the
    /// higher-precedence OFF argument was not.
    static var isForcedOnForDebugging: Bool { forceOnRequested && !forceOffRequested }

    /// `true` when `-PRO_GATING_OFF` decided this run. It always does when
    /// passed, since it wins over both the ON argument and `shippedValue`.
    static var isForcedOffForDebugging: Bool { forceOffRequested }
    #endif
}
