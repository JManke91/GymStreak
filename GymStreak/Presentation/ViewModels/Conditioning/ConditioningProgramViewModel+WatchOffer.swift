//
//  ConditioningProgramViewModel+WatchOffer.swift
//  GymStreak
//
//  What the watch offers for conditioning (docs/fight-conditioning.md, ticket 06):
//  this week's open targets while the program is running, today's suggestion
//  first, with the personal heart-rate range already computed.
//

import Foundation

extension ConditioningProgramViewModel {

    static func watchOffer(
        dashboard: ConditioningProgramDashboard?,
        today: ConditioningProgramDay,
        profile: HeartRateProfile?,
        calendar: Calendar,
        now: Date
    ) -> ConditioningWatchOffer {
        let startOfToday = calendar.startOfDay(for: now)
        guard let dashboard,
              case .active(_, _, let isPaused) = dashboard.status, !isPaused,
              // The P12 gate reaches the watch here and **only** here (ticket
              // 08). A locked week publishes an empty offer, so the watch simply
              // has no conditioning to show — it never learns that a gate
              // exists, never renders a lock and never renders a paywall, which
              // is what §3 Rule 3 requires of it.
              !dashboard.isLocked,
              let weekEnd = calendar.date(
                byAdding: .day,
                value: 7,
                to: ConditioningProgramSchedule
                    .currentWeekStart(on: today, enrollment: dashboard.enrollment, calendar: calendar)
                    .startDate(in: calendar)
              ) else {
            return .none(on: startOfToday)
        }
        var suggested: ConditioningSessionDefinition.ID?
        if case .session(let target, _) = dashboard.suggestion { suggested = target.session }

        let sessions = dashboard.progress
            .filter { $0.remaining > 0 }
            .map { progress -> ConditioningWatchOffer.Session in
                let definition = progress.target.definition
                return ConditioningWatchOffer.Session(
                    plan: ConditioningSessionPlan(
                        definition: definition,
                        options: progress.target.options,
                        // The session's own default, as the iPhone preview opens on; the
                        // watch offers the other modalities as a choice.
                        modality: definition.modalities.first ?? .run
                    ),
                    isSuggestedToday: progress.target.session == suggested,
                    heartRateTarget: HeartRateZones.target(for: definition.effort, profile: profile)
                )
            }
        return ConditioningWatchOffer(
            sessions: sessions.filter(\.isSuggestedToday) + sessions.filter { !$0.isSuggestedToday },
            day: startOfToday,
            validUntil: weekEnd
        )
    }
}
