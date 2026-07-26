//
//  HistorySnapshotBuilder.swift
//  GymStreak
//

import Foundation

/// Builds the whole `HistorySnapshot` in one traversal of the session graph.
///
/// Replaces what the Trainings tab used to do inside `body`: `weekStats`, `weekDayStatuses`,
/// `groupByMonth`, `plannedWeek` (read twice) and `lastMonthStats` were five independent
/// aggregations, three of them walking every session's every set, all re-run on every render.
/// Here each session is visited exactly once and every aggregate is accumulated from that visit.
///
/// Pure and synchronous: it takes models fetched by the caller's context and returns values. The
/// production caller is a Data-layer `@ModelActor`; unit tests call it with an in-memory context.
struct HistorySnapshotBuilder {

    /// - Parameters:
    ///   - sessions: sessions to summarise, in any order. Unfinished ones are dropped and the rest
    ///     sorted newest-first here rather than trusted from the caller: month ordering, in-month
    ///     card ordering and every count depend on both, and `PersonalRecordService` sets the
    ///     precedent of normalising its own input.
    ///   - routines: live routines, for the dynamic weekly goal.
    ///   - prCountBySession: PR counts from `PersonalRecordService`, computed once by the caller.
    static func build(
        sessions incoming: [WorkoutSession],
        routines: [Routine],
        prCountBySession: [UUID: Int],
        referenceDate: Date = Date()
    ) -> HistorySnapshot {
        let calendar = HistoryStatsService.isoGermanCalendar()
        let sessions = incoming
            .filter { $0.endTime != nil }
            .sorted { $0.startTime > $1.startTime }

        // `plannedWeek` walks routines × sessions and faults `session.routine?.id`; it used to be a
        // computed property read twice per render. Once, here.
        let plannedWeek = WorkoutPlanningService.plannedWeek(
            routines: routines,
            completedSessions: sessions
        )

        let lastMonthInterval = Self.lastMonthInterval(calendar: .current, referenceDate: referenceDate)

        var cardsByDay: [Date: WorkoutCardModel] = [:]
        var cardsByMonth: [MonthKey: [WorkoutCardModel]] = [:]
        var volumeByMonth: [MonthKey: Double] = [:]
        var countByMonth: [MonthKey: Int] = [:]
        var typesByMonth: [MonthKey: [WorkoutType]] = [:]
        var seenTypesByMonth: [MonthKey: Set<WorkoutType>] = [:]
        var monthOrder: [MonthKey] = []
        var lastMonthCount = 0
        var lastMonthVolume = 0.0
        var lastMonthPRs = 0

        // The single pass. Every per-session aggregate below comes from this one visit.
        for session in sessions {
            let totals = session.aggregates
            let prLifts = prCountBySession[session.id] ?? 0
            let card = WorkoutCardModel(
                id: session.id,
                startTime: session.startTime,
                routineName: session.routineName,
                type: WorkoutType.classify(routineName: session.routineName),
                durationMinutes: max(0, Int(session.duration / 60)),
                completedSets: totals.completedSets,
                totalVolume: totals.volume,
                completionPercentage: totals.completionPercentage,
                prLifts: prLifts
            )
            let components = calendar.dateComponents([.year, .month], from: session.startTime)
            if let year = components.year, let month = components.month {
                let key = MonthKey(year: year, month: month)
                if countByMonth[key] == nil { monthOrder.append(key) }
                countByMonth[key, default: 0] += 1
                volumeByMonth[key, default: 0] += totals.volume
                cardsByMonth[key, default: []].append(card)
                if seenTypesByMonth[key, default: []].insert(card.type).inserted {
                    typesByMonth[key, default: []].append(card.type)
                }
            }

            // Calendar mode shows one card per day; on a double-workout day the later one wins.
            let day = calendar.startOfDay(for: session.startTime)
            if let existing = cardsByDay[day] {
                if session.startTime > existing.startTime { cardsByDay[day] = card }
            } else {
                cardsByDay[day] = card
            }

            if let interval = lastMonthInterval, interval.contains(session.startTime) {
                lastMonthCount += 1
                lastMonthVolume += totals.volume
                lastMonthPRs += prLifts
            }
        }

        let monthSections = monthOrder.map { key in
            MonthSectionModel(
                year: key.year,
                month: key.month,
                label: HistoryStatsService.monthYearLabel(year: key.year, month: key.month),
                sessionCount: countByMonth[key] ?? 0,
                totalVolume: volumeByMonth[key] ?? 0
            )
        }

        return HistorySnapshot(
            rows: Self.flatten(monthSections: monthSections, cardsByMonth: cardsByMonth),
            weekStats: HistoryStatsService.weekStats(
                sessions: sessions,
                prExerciseCountBySession: prCountBySession,
                goal: plannedWeek.goal,
                referenceDate: referenceDate
            ),
            weekDays: HistoryStatsService.weekDayStatuses(
                sessions: sessions,
                plannedDates: plannedWeek.plannedDates,
                referenceDate: referenceDate
            ),
            lastMonth: HistorySnapshot.LastMonthStats(
                label: lastMonthInterval.map { HistoryStatsService.monthYearLabel(for: $0.start) } ?? "",
                count: lastMonthCount,
                volumeTons: lastMonthVolume / 1000.0,
                prs: lastMonthPRs
            ),
            cardsByDay: cardsByDay,
            monthTotals: Dictionary(uniqueKeysWithValues: monthSections.map { ($0.id, $0) }),
            typesByMonth: Dictionary(uniqueKeysWithValues: typesByMonth.map { key, types in
                (MonthSectionModel.id(year: key.year, month: key.month), types)
            }),
            sessionCount: sessions.count
        )
    }

    // MARK: - Row flattening

    /// Interleaves month dividers with their cards into one sequence.
    ///
    /// The first month deliberately gets no divider — that matches the established design, where
    /// the dividers separate months rather than title them. Sessions were sorted newest-first, so
    /// months and the cards within each month are already in the right order; no sorting here.
    private static func flatten(
        monthSections: [MonthSectionModel],
        cardsByMonth: [MonthKey: [WorkoutCardModel]]
    ) -> [HistoryListRow] {
        var rows: [HistoryListRow] = []
        for (index, section) in monthSections.enumerated() {
            if index > 0 {
                rows.append(.monthHeader(section))
            }
            let key = MonthKey(year: section.year, month: section.month)
            rows.append(contentsOf: (cardsByMonth[key] ?? []).map { HistoryListRow.card($0) })
        }
        return rows
    }

    private static func lastMonthInterval(calendar: Calendar, referenceDate: Date) -> DateInterval? {
        guard let previous = calendar.date(byAdding: .month, value: -1, to: referenceDate),
              let interval = calendar.dateInterval(of: .month, for: previous) else { return nil }
        return interval
    }

    private struct MonthKey: Hashable {
        let year: Int
        let month: Int
    }
}
