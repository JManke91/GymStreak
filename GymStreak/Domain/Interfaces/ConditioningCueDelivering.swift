//
//  ConditioningCueDelivering.swift
//  GymStreak
//
//  The conditioning runner's cue outputs: an immediate sound + haptic while the
//  app is on screen, and local notifications for the transitions that fall
//  while it is backgrounded or the phone is locked. The round timer plays its
//  bell through the same outputs (docs/fight-conditioning.md, "Round timer").
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
    /// Round timer: the bell that starts a round.
    case roundStart
    /// Round timer: the clacker a few seconds before a round ends.
    case roundWarning
    /// Round timer: the bell that ends a round.
    case roundEnd
    /// Round timer: the last round is over.
    case roundTimerFinished
}

/// A transition delivered as a local notification. Text is built by the
/// caller, which owns the localized phase vocabulary.
struct ConditioningScheduledCue: Equatable, Sendable {
    let fireDate: Date
    let title: String
    let body: String
    /// The live cue this notification stands in for; decides its sound. `nil`
    /// plays the default notification sound.
    var cue: ConditioningLiveCue? = nil
}

@MainActor
protocol ConditioningCueDelivering: AnyObject {
    func play(_ cue: ConditioningLiveCue)

    /// Replaces every pending conditioning notification with `cues`, which are
    /// in time order — the deliverer keeps the earliest ones when there are
    /// more than it may schedule.
    /// - Returns: `false` when notifications are not allowed, so the runner can
    ///   tell the user cues will only play while the screen is on.
    @discardableResult
    func scheduleBackgroundCues(_ cues: [ConditioningScheduledCue]) async -> Bool

    func cancelBackgroundCues()

    /// Loads what the round timer's bell needs before its first ring, so the
    /// opening bell is not the moment the audio session is first configured.
    func prepareRoundTimer()
}

extension ConditioningCueDelivering {
    func prepareRoundTimer() {}
}
