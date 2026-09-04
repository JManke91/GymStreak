//
//  OnboardingCompletionTracking.swift
//  GymStreak
//
//  Whether the first-run onboarding flow has already been seen on this install.
//  See docs/onboarding.md.
//

import Foundation

/// The durable "the onboarding flow has been completed" record.
///
/// Deliberately **device-local** and deliberately **not conditioned on the
/// install's content**: everyone meets the flow exactly once, existing users
/// updating into this version included. Two consequences follow, and both are
/// intentional:
///
/// - **Plain `UserDefaults.standard`, never iCloud KVS.** A KVS flag survives an
///   app deletion (the trap the starter-catalog seeding flags already fell into),
///   which would leave a reinstalling user staring at the tab bar with no idea
///   what the app is. Being toured twice on a second device is the cheaper
///   mistake.
/// - **Not the App Group suite** — neither the watch app nor the widget shows
///   onboarding.
///
/// `@MainActor` like the rest of the presentation-history protocols, and it
/// imports nothing beyond Foundation on purpose: no `UserDefaults` key may
/// appear in this signature.
@MainActor
protocol OnboardingCompletionTracking: AnyObject {

    /// Whether the flow has already been seen. Cheap by contract — it is asked
    /// while the app root is being built, so a conformer answers from memory
    /// rather than from I/O.
    var hasCompletedOnboarding: Bool { get }

    /// Records that the flow was finished or skipped. Idempotent, one-way:
    /// nothing ever un-onboards.
    func recordCompleted()
}
