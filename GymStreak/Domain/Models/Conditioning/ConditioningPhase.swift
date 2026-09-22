//
//  ConditioningPhase.swift
//  GymStreak
//
//  The timed building blocks of a conditioning session — what the timeline
//  engine runs on. IDENTICAL COPY in both targets (iOS `Domain/Models/
//  Conditioning/`, watch `Models/Conditioning/`): the iPhone expands a plan
//  into phases and syncs them; the watch runs them. Change both together —
//  `WatchConditioningTimelineTests` covers the watch copy.
//  See docs/fight-conditioning.md.
//

import Foundation

/// The intensity cue shown for a phase, as RPE / talk test. The conversational
/// effort additionally gets a personal heart-rate range (`HeartRateZones`).
enum ConditioningEffort: String, Codable, Sendable {
    /// Warm-up, cool-down and recovery: easy movement.
    case easy
    /// Aerobic base: RPE 3–4, can hold a conversation.
    case conversational
    /// Aerobic-maintenance bursts: RPE 8.
    case strongBurst
    /// Lactic intervals: RPE 9, hard but repeatable.
    case hardRepeatable
    /// Alactic power: maximal intent.
    case maximal
    /// The beginner variant of alactic power: 85–90 %.
    case subMaximal
}

enum ConditioningPhaseKind: String, Codable, Sendable {
    case warmUp, work, rest, setBreak, coolDown, steady

    /// Whether the phase is effort the user has to produce — the phases that
    /// get a 3-2-1 lead-in and count as "the session has begun".
    var isEffort: Bool { self == .work || self == .steady }
}

/// One timed block of a session.
struct ConditioningPhase: Codable, Equatable, Sendable {
    let kind: ConditioningPhaseKind
    let duration: TimeInterval
    let effort: ConditioningEffort
    /// 1-based round within the current set, for work/rest phases.
    let round: Int?
    let roundsPerSet: Int?
    /// 1-based set, for sessions organized in sets.
    let set: Int?
    let totalSets: Int?

    init(
        kind: ConditioningPhaseKind,
        duration: TimeInterval,
        effort: ConditioningEffort,
        round: Int? = nil,
        roundsPerSet: Int? = nil,
        set: Int? = nil,
        totalSets: Int? = nil
    ) {
        self.kind = kind
        self.duration = duration
        self.effort = effort
        self.round = round
        self.roundsPerSet = roundsPerSet
        self.set = set
        self.totalSets = totalSets
    }
}
