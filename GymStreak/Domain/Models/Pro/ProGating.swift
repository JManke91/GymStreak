//
//  ProGating.swift
//  GymStreak
//
//  The single global switch that turns Pro gating on. Ships off.
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

    /// What a shipping build does. `false` until the Phase 2 launch release
    /// (ticket 15) flips it — this is the constant that flip changes.
    ///
    /// Read `isEnabled`, not this, everywhere except the assertion that pins the
    /// shipped value.
    static let shippedValue = false

    /// Whether gating is live in *this* run.
    ///
    /// `shippedValue`, unless a Debug build was launched with
    /// `-PRO_GATING_ON`. That argument exists because the alternative is worse:
    /// every gate, the paywall, the Settings subscription section and the
    /// Founder screen are inert while the switch is off, so exercising any of
    /// them used to mean editing `shippedValue` and remembering not to commit
    /// it.
    ///
    /// The scheme is shared and tracked, so ticking the argument *is* a diff —
    /// but a visible one-attribute diff in `GymStreak.xcscheme`, not a semantic
    /// change to Swift that reads as intentional. The guarantee that matters is
    /// that the argument is `#if DEBUG`, so it cannot affect a shipping build
    /// however it is left.
    ///
    /// A `static let`, so `ProcessInfo` is read once and the value cannot change
    /// under a gate mid-session — the flag is a launch property, not a setting.
    /// Reading `ProcessInfo` here does not compromise `Domain/`: it is neither
    /// persistence nor a Data type, and the alternative (injecting an effective
    /// flag from the composition root) would have to reach the eight call sites
    /// that take this as a default argument.
    static let isEnabled: Bool = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(forceOnLaunchArgument) {
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
        if isForcedOnForDebugging {
            return "forced by \(forceOnLaunchArgument)"
        }
        return "shippedValue; \(forceOnLaunchArgument) not passed — Xcode scheme arguments are "
            + "absent on a manual relaunch"
        #else
        return "shippedValue"
        #endif
    }

    #if DEBUG
    /// Add to the scheme under Run → Arguments → Arguments Passed On Launch.
    static let forceOnLaunchArgument = "-PRO_GATING_ON"

    /// `true` when this run's gating comes from the launch argument rather than
    /// from `shippedValue`, so the debug sections can say which it is.
    static var isForcedOnForDebugging: Bool { isEnabled && !shippedValue }
    #endif
}
