//
//  WatchCompletedConditioningSession+Run.swift
//  GymStreakWatch Watch App
//
//  What the watch sends the iPhone for History once a run ends (ticket 07,
//  docs/fight-conditioning.md). Mirrors the iPhone's `ConditioningRecord.make`:
//  every number comes from the timeline that actually ran.
//

import Foundation

extension WatchCompletedConditioningSession {

    /// - Parameter elapsed: session time at the moment it ended, pauses excluded.
    static func make(
        id: UUID,
        session: WatchConditioningSession,
        modality: String,
        title: String,
        timeline: ConditioningTimeline,
        startDate: Date,
        endDate: Date,
        elapsed: TimeInterval,
        endedEarly: Bool,
        isSavedToHealth: Bool
    ) -> WatchCompletedConditioningSession {
        let phases = timeline.phases
        let work = phases.first { $0.kind == .work }
        return WatchCompletedConditioningSession(
            id: id,
            startTime: startDate,
            endTime: endDate,
            sessionType: session.sessionType,
            title: title,
            energySystem: session.energySystem,
            modality: modality,
            effort: (phases.first { $0.kind.isEffort }?.effort ?? .easy).rawValue,
            roundsCompleted: timeline.completedWorkIntervals(at: elapsed),
            roundsPlanned: timeline.workIntervalCount,
            setsPlanned: work?.totalSets ?? 0,
            workInterval: work?.duration ?? 0,
            restInterval: phases.first { $0.kind == .rest }?.duration ?? 0,
            endedEarly: endedEarly,
            isSavedToHealth: isSavedToHealth
        )
    }
}
