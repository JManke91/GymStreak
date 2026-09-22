//
//  ConditioningRunCues.swift
//  GymStreakWatch Watch App
//
//  Which haptic cues a tick of the watch conditioning runner plays, and when
//  the heart-rate zone nudge fires. Pure and time-in-session based, so both
//  are unit-tested (`WatchConditioningRunCuesTests`) and a paused clock can
//  never produce a cue. See docs/fight-conditioning.md (ticket 06).
//

import Foundation

enum ConditioningRunCue: Equatable {
    /// A work or steady phase begins.
    case effortStart
    /// A rest, set break or cool-down begins.
    case recoveryStart
    /// 3-2-1 before an effort phase that follows another phase.
    case leadIn(Int)
    /// The last phase ended.
    case finished
}

enum ConditioningCueEvaluator {

    /// A tick further apart than this is a catch-up (the process was not
    /// running, or a recovered session resumed): jump to the current phase
    /// without replaying what happened meanwhile — the iPhone runner's rule.
    static let maximumTickGap: TimeInterval = 2

    static func cues(
        in timeline: ConditioningTimeline,
        from previous: TimeInterval,
        to current: TimeInterval
    ) -> [ConditioningRunCue] {
        guard current > previous, current - previous <= maximumTickGap else { return [] }
        func crossed(_ offset: TimeInterval) -> Bool { offset > previous && offset <= current }

        var cues: [ConditioningRunCue] = []
        for index in timeline.phases.indices.dropFirst() {
            let offset = timeline.startOffsets[index]
            let phase = timeline.phases[index]
            if phase.kind.isEffort {
                for count in (1...3).reversed() where crossed(offset - TimeInterval(count)) {
                    cues.append(.leadIn(count))
                }
            }
            if crossed(offset) {
                cues.append(phase.kind.isEffort ? .effortStart : .recoveryStart)
            }
        }
        if crossed(timeline.totalDuration) { cues.append(.finished) }
        return cues
    }
}

/// Where the live heart rate sits against the synced personal range.
enum ConditioningZoneStatus: Equatable {
    case below, inZone, above

    init(heartRate: Int, zone: WatchHeartRateZone) {
        if heartRate < zone.lowerBPM {
            self = .below
        } else if heartRate > zone.upperBPM {
            self = .above
        } else {
            self = .inZone
        }
    }
}

/// Nudges the user only after a *sustained* drift out of zone, then at most once
/// a minute while it lasts — heart rate lags effort, and a buzz on every sample
/// would train the user to ignore it.
struct ConditioningZoneMonitor: Equatable {
    static let sustainedDrift: TimeInterval = 30
    static let repeatInterval: TimeInterval = 60

    private var driftStatus: ConditioningZoneStatus?
    private var driftStartedAt: TimeInterval?
    private var lastNudgeAt: TimeInterval?

    /// Feeds the status at session time `elapsed`; returns the status to nudge
    /// about, or `nil`. `nil` in means "no zone applies right now" (another
    /// phase, no reading yet) and resets the drift like being in zone does.
    mutating func update(_ status: ConditioningZoneStatus?, at elapsed: TimeInterval) -> ConditioningZoneStatus? {
        guard let status, status != .inZone else {
            self = ConditioningZoneMonitor()
            return nil
        }
        if status != driftStatus {
            driftStatus = status
            driftStartedAt = elapsed
            lastNudgeAt = nil
        }
        guard let driftStartedAt, elapsed - driftStartedAt >= Self.sustainedDrift else { return nil }
        if let lastNudgeAt, elapsed - lastNudgeAt < Self.repeatInterval { return nil }
        lastNudgeAt = elapsed
        return status
    }
}
