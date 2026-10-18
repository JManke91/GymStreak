//
//  RoundTimerConfiguration.swift
//  GymStreak
//
//  The round timer for sparring and class rounds (positioning ticket 07,
//  docs/fight-conditioning.md "Round timer"): the sport presets, the user's
//  settings, and their expansion into the phases the conditioning timeline
//  runs — no timer engine of its own. IDENTICAL COPY in both targets (iOS
//  `Domain/Models/Conditioning/`, watch `Models/Conditioning/`): each device
//  expands its own rounds, so the watch runs without the iPhone. Change both
//  together — `WatchRoundTimerTests.sharedCopiesMatch` covers the watch copy.
//

import Foundation

/// A preset stands for a sport: it fixes round and rest length and names the
/// mat session the timer can be saved as. `custom` lets the user set both and
/// is saved as "other".
enum RoundTimerPreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case bjj, mma, boxing, muayThai, custom

    var id: String { rawValue }

    /// Round length in seconds; `nil` for custom, which the user sets.
    var roundDuration: TimeInterval? {
        switch self {
        case .bjj, .mma: 5 * 60
        case .boxing, .muayThai: 3 * 60
        case .custom: nil
        }
    }

    /// Rest length in seconds; `nil` for custom.
    var restDuration: TimeInterval? {
        switch self {
        case .bjj, .mma, .boxing: 60
        case .muayThai: 2 * 60
        case .custom: nil
        }
    }

    /// The `MatSport` / `WatchMatSport` raw value a session timed with this
    /// preset is pre-filled with.
    var matSportRawValue: String {
        switch self {
        case .bjj: "bjj"
        case .mma: "mma"
        case .boxing: "boxing"
        case .muayThai: "muayThai"
        case .custom: "other"
        }
    }
}

/// What the user set up for a run; the last one used is remembered per device.
struct RoundTimerConfiguration: Codable, Equatable, Sendable {
    static let roundDurationRange: ClosedRange<TimeInterval> = 30...(20 * 60)
    static let restDurationRange: ClosedRange<TimeInterval> = 0...(10 * 60)
    static let roundsRange = 1...30
    static let warningRange: ClosedRange<TimeInterval> = 0...30
    /// An open-ended timer runs rounds until the user stops it. The timeline is
    /// finite, so "open-ended" is this many rounds — more than any class.
    static let openEndedRoundCount = 99

    var preset: RoundTimerPreset
    /// Round and rest length when `preset` is `.custom`; kept while another
    /// preset is selected so switching back restores them.
    var customRoundDuration: TimeInterval
    var customRestDuration: TimeInterval
    /// `nil` is open-ended.
    var rounds: Int?
    /// Seconds before a round ends at which the warning sounds; 0 turns it off.
    var warning: TimeInterval

    static let `default` = RoundTimerConfiguration(
        preset: .bjj,
        customRoundDuration: 3 * 60,
        customRestDuration: 60,
        rounds: 6,
        warning: 10
    )

    var roundDuration: TimeInterval { preset.roundDuration ?? customRoundDuration }
    var restDuration: TimeInterval { preset.restDuration ?? customRestDuration }
    var isOpenEnded: Bool { rounds == nil }
    var plannedRounds: Int { rounds ?? Self.openEndedRoundCount }

    /// Rounds plus the rests between them; `nil` when open-ended.
    var totalDuration: TimeInterval? {
        guard let rounds else { return nil }
        return TimeInterval(rounds) * roundDuration + TimeInterval(max(0, rounds - 1)) * restDuration
    }

    /// The phases the conditioning timeline runs: round, rest, round, … with no
    /// rest after the last round. A rest of 0 is left out, so the next round
    /// starts on the bell.
    func phases() -> [ConditioningPhase] {
        var phases: [ConditioningPhase] = []
        for round in 1...plannedRounds {
            phases.append(ConditioningPhase(
                kind: .work,
                duration: roundDuration,
                effort: .hardRepeatable,
                round: round,
                roundsPerSet: rounds
            ))
            if round < plannedRounds, restDuration > 0 {
                phases.append(ConditioningPhase(
                    kind: .rest,
                    duration: restDuration,
                    effort: .easy,
                    round: round,
                    roundsPerSet: rounds
                ))
            }
        }
        return phases
    }
}

extension ConditioningTimeline {
    /// Session-relative moments at which a work phase has `warning` seconds
    /// left — the round timer's end-of-round warning. Rounds no longer than
    /// the warning get none, and a warning of 0 means no warnings at all.
    func warningOffsets(before warning: TimeInterval) -> [TimeInterval] {
        guard warning > 0 else { return [] }
        return phases.indices.compactMap { index in
            let phase = phases[index]
            guard phase.kind == .work, phase.duration > warning else { return nil }
            return startOffsets[index] + phase.duration - warning
        }
    }
}
