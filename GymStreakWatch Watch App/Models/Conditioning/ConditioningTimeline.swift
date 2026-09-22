//
//  ConditioningTimeline.swift
//  GymStreak
//
//  Pure timing for a conditioning session: the phase sequence a plan expands
//  to, and where a given elapsed time falls in it. The runner never counts
//  down — it asks the timeline "where am I at elapsed t?", with t derived from
//  wall-clock dates by `ConditioningClock`, so backgrounding or a locked screen
//  cannot drift the countdown. See docs/fight-conditioning.md.
//
//  IDENTICAL COPY in both targets (iOS `Domain/Services/`, watch
//  `Models/Conditioning/`) — the watch runs the phases the iPhone expanded
//  (`ConditioningTimeline+Expansion.swift`, iOS only). Change both together;
//  `WatchConditioningTimelineTests` covers the watch copy.
//

import Foundation

struct ConditioningPosition: Equatable, Sendable {
    let phaseIndex: Int
    let phase: ConditioningPhase
    let elapsedInPhase: TimeInterval
    var remainingInPhase: TimeInterval { phase.duration - elapsedInPhase }
}

struct ConditioningTimeline: Equatable, Sendable {
    let phases: [ConditioningPhase]
    /// Session-relative start of each phase, parallel to `phases`.
    let startOffsets: [TimeInterval]
    let totalDuration: TimeInterval
    /// Start of the first effort phase — ending before it means the session
    /// never really began and nothing is saved. Stored: the runner asks on
    /// every render.
    let firstEffortOffset: TimeInterval?

    init(phases: [ConditioningPhase]) {
        self.phases = phases
        var offsets: [TimeInterval] = []
        var cursor: TimeInterval = 0
        for phase in phases {
            offsets.append(cursor)
            cursor += phase.duration
        }
        self.startOffsets = offsets
        self.totalDuration = cursor
        self.firstEffortOffset = phases.indices.first { phases[$0].kind.isEffort }.map { offsets[$0] }
    }

    /// Whether the session has progressed into its first effort phase.
    func hasBegunEffort(at elapsed: TimeInterval) -> Bool {
        guard let offset = firstEffortOffset else { return false }
        return elapsed > offset
    }

    /// Work intervals the plan contains. 0 for steady state, which has none —
    /// that is also what `ConditioningRecord.isSteadyState` reads.
    var workIntervalCount: Int {
        phases.filter { $0.kind == .work }.count
    }

    /// Work intervals *fully* finished at `elapsed`. A round the user is still
    /// in does not count: History says what was completed, not what was started.
    func completedWorkIntervals(at elapsed: TimeInterval) -> Int {
        phases.indices.filter { index in
            phases[index].kind == .work && startOffsets[index] + phases[index].duration <= elapsed
        }.count
    }

    /// The phase covering `elapsed`; `nil` once the session is over.
    func position(at elapsed: TimeInterval) -> ConditioningPosition? {
        guard elapsed < totalDuration else { return nil }
        let clamped = max(0, elapsed)
        // Last phase whose start is at or before `clamped`.
        guard let index = startOffsets.lastIndex(where: { $0 <= clamped }) else { return nil }
        return ConditioningPosition(
            phaseIndex: index,
            phase: phases[index],
            elapsedInPhase: clamped - startOffsets[index]
        )
    }

    /// Phase starts strictly after `elapsed` (index into `phases` with its
    /// offset) — what the background cue scheduler needs.
    func upcomingPhaseStarts(after elapsed: TimeInterval) -> [(index: Int, offset: TimeInterval)] {
        phases.indices
            .filter { startOffsets[$0] > elapsed }
            .map { ($0, startOffsets[$0]) }
    }
}

/// Wall-clock elapsed time with pauses subtracted. Value type, so the runner
/// owns it and tests can drive it with fixed dates.
struct ConditioningClock: Codable, Equatable, Sendable {
    private(set) var startDate: Date?
    private(set) var pausedAt: Date?
    private(set) var pausedTotal: TimeInterval = 0

    var isRunning: Bool { startDate != nil && pausedAt == nil }
    var isPaused: Bool { pausedAt != nil }

    mutating func start(at date: Date) {
        startDate = date
        pausedAt = nil
        pausedTotal = 0
    }

    mutating func pause(at date: Date) {
        guard isRunning else { return }
        pausedAt = date
    }

    mutating func resume(at date: Date) {
        guard let pausedAt else { return }
        pausedTotal += max(0, date.timeIntervalSince(pausedAt))
        self.pausedAt = nil
    }

    func elapsed(at now: Date) -> TimeInterval {
        guard let startDate else { return 0 }
        let reference = pausedAt ?? now
        return max(0, reference.timeIntervalSince(startDate) - pausedTotal)
    }

    /// The wall-clock date at which session-relative `offset` is reached if the
    /// clock keeps running from `now` — only meaningful while running.
    func date(forElapsed offset: TimeInterval, now: Date) -> Date {
        now.addingTimeInterval(offset - elapsed(at: now))
    }
}
