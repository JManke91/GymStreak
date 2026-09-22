//
//  WatchConditioningRunViewModel+Display.swift
//  GymStreakWatch Watch App
//
//  The values the redesigned runner pages draw, derived from the run's position
//  so the views compute nothing (docs/fight-conditioning.md, watch runner redesign).
//

import Foundation

/// What the runner shows for heart rate. The first sample of a workout session
/// takes a few seconds; without one after `measuringWindow` of session time the
/// sensor is not delivering (loose fit, or Health read access denied).
enum ConditioningHeartRateReading: Equatable {
    case measuring
    case missing
    case bpm(Int)

    static let measuringWindow: TimeInterval = 30

    var bpm: Int? {
        if case .bpm(let bpm) = self { return bpm }
        return nil
    }
}

extension WatchConditioningRunViewModel {

    var heartRateReading: ConditioningHeartRateReading {
        if let heartRate { return .bpm(heartRate) }
        // From when delivery (re)started — a recovered session is not "missing" at once.
        return elapsed - heartRateSearchStartedAt < ConditioningHeartRateReading.measuringWindow ? .measuring : .missing
    }

    /// Steady state gets the heart-rate gauge page; everything else (warm-up,
    /// work, rest, set break, cool-down) the phase-countdown page.
    var showsZonePage: Bool { position?.phase.kind == .steady }

    /// 3, 2, 1 in the last seconds before an effort phase that follows another.
    var leadInCount: Int? {
        guard let position, !position.phase.kind.isEffort, nextPhase?.kind.isEffort == true else { return nil }
        let seconds = Int(position.remainingInPhase.rounded(.up))
        return (1...3).contains(seconds) ? seconds : nil
    }

    /// Share of the current phase still to go — the interval page's ring.
    var phaseRemainingFraction: Double {
        guard let position, position.phase.duration > 0 else { return 0 }
        return max(0, min(1, position.remainingInPhase / position.phase.duration))
    }

    /// Share of the session done — the ring when no heart-rate range applies.
    var sessionFraction: Double {
        guard totalDuration > 0 else { return 0 }
        return max(0, min(1, elapsed / totalDuration))
    }

    /// Rounds of the current set for the dot row: finished rounds, and the one in
    /// progress during a work phase. `nil` outside the interval block.
    var roundProgress: (completed: Int, current: Int?, total: Int)? {
        guard let phase = position?.phase else { return nil }
        if phase.kind == .setBreak, let total = nextPhase?.roundsPerSet ?? phase.roundsPerSet {
            return (total, nil, total)
        }
        guard let round = phase.round, let total = phase.roundsPerSet else { return nil }
        return phase.kind == .work ? (round - 1, round - 1, total) : (round, nil, total)
    }
}
