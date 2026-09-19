//
//  ConditioningCueDelivering.swift
//  GymStreak
//
//  The conditioning runner's cue outputs: an immediate sound + haptic while the
//  app is on screen, and local notifications for the transitions that fall
//  while it is backgrounded or the phone is locked. See
//  docs/fight-conditioning.md.
//

import Foundation

/// A cue played right now, while the runner is visible.
enum ConditioningLiveCue: Sendable {
    /// One tick of the 3-2-1 lead-in before a work interval.
    case leadIn
    /// An effort phase begins.
    case effortStart
    /// A recovery phase (rest, set break, warm-up, cool-down) begins.
    case recoveryStart
    case finished
}

/// A transition delivered as a local notification. Text is built by the
/// caller, which owns the localized phase vocabulary.
struct ConditioningScheduledCue: Equatable, Sendable {
    let fireDate: Date
    let title: String
    let body: String
}

@MainActor
protocol ConditioningCueDelivering: AnyObject {
    func play(_ cue: ConditioningLiveCue)

    /// Replaces every pending conditioning notification with `cues`.
    /// - Returns: `false` when notifications are not allowed, so the runner can
    ///   tell the user cues will only play while the screen is on.
    @discardableResult
    func scheduleBackgroundCues(_ cues: [ConditioningScheduledCue]) async -> Bool

    func cancelBackgroundCues()
}
