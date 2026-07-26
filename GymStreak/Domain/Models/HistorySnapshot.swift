//
//  HistorySnapshot.swift
//  GymStreak
//

import Foundation

/// Everything the History screen's Trainings tab renders, precomputed once.
///
/// This exists because the screen used to derive all of it *inside* `body`: five whole-history
/// aggregations per render, plus four traversals of `workoutExercises → sets` per visible card.
/// At a few hundred sessions that saturated the main thread for over half a second on entry and
/// again every time the scroll view re-laid out. See docs/history-performance.md.
///
/// These are computed aggregates, not a DTO mirror of the stored rows — `docs/architecture.md`
/// prohibits a DTO/mapper layer over the local store, and this is not one. They live in `Domain/`
/// rather than `Presentation/` so a background aggregator in `Data/` can produce them without
/// Data depending on Presentation (see "Step B" in docs/history-performance.md).
struct HistorySnapshot: Sendable {
    /// The Trainings list, already flattened into a single sequence of rows so the view can use
    /// one non-nested `LazyVStack`.
    var rows: [HistoryListRow]
    var weekStats: HistoryStatsService.WeekStats
    var weekDays: [HistoryStatsService.WeekDayStatus]
    var lastMonth: LastMonthStats
    /// One card per day that has a finished workout, for the calendar mode's day cells and its
    /// selected-day detail. Keyed by start-of-day.
    var cardsByDay: [Date: WorkoutCardModel]
    /// Per-**session** totals for every month, keyed `"year-month"`.
    ///
    /// The calendar's month header needs these and cannot derive them from `cardsByDay`, which holds
    /// one card per *day*: on a two-workout day that undercounts the sessions and loses the earlier
    /// workout's volume outright, and it would disagree with the list's own divider for the same
    /// month. Nor can it read them from `rows` — the newest month deliberately has no divider row.
    var monthTotals: [String: MonthSectionModel]
    /// Workout types present in each month, keyed `"year-month"`, newest session first. Same reason:
    /// a per-day view of the data can drop a type the month actually contains.
    var typesByMonth: [String: [WorkoutType]]
    /// Completed sessions the snapshot was built from. Drives empty-state and change detection.
    var sessionCount: Int

    static let empty = HistorySnapshot(
        rows: [],
        weekStats: HistoryStatsService.WeekStats(
            completedCount: 0,
            goal: 0,
            weekVolume: 0,
            volumeTrendPct: nil,
            prCount: 0,
            streakWeeks: 0
        ),
        weekDays: [],
        lastMonth: LastMonthStats(label: "", count: 0, volumeTons: 0, prs: 0),
        cardsByDay: [:],
        monthTotals: [:],
        typesByMonth: [:],
        sessionCount: 0
    )

    /// Subline values for the AI Coach entry card.
    struct LastMonthStats: Sendable {
        let label: String
        let count: Int
        let volumeTons: Double
        let prs: Int
    }
}

/// One row of the Trainings list: either a month divider or a workout card.
///
/// Flattened deliberately. Nesting a `LazyVStack` of cards inside a `LazyVStack` of month groups
/// is an undocumented shape with corroborated reports of scroll stutter and at least one
/// reproducible hang; a single level avoids the question entirely.
enum HistoryListRow: Identifiable, Hashable, Sendable {
    case monthHeader(MonthSectionModel)
    case card(WorkoutCardModel)

    var id: String {
        switch self {
        case .monthHeader(let month): return "month-\(month.id)"
        case .card(let card):         return "card-\(card.id.uuidString)"
        }
    }
}

/// Month divider values. `sessionCount` and `totalVolume` come from the same single pass that
/// builds the cards, rather than a second walk of the whole history.
struct MonthSectionModel: Identifiable, Hashable, Sendable {
    let year: Int
    let month: Int
    let label: String
    let sessionCount: Int
    let totalVolume: Double

    var id: String { Self.id(year: year, month: month) }

    /// The one definition of the month key format, shared by `monthTotals` and `typesByMonth` so a
    /// lookup cannot silently miss because two call sites formatted it differently.
    static func id(year: Int, month: Int) -> String { "\(year)-\(month)" }
}

/// Display-ready values for one workout card.
///
/// A row view takes this, never a `WorkoutSession`. Reading a SwiftData `@Relationship` per row is
/// an N+1 fault, and the derived properties on `WorkoutSession` each walk the whole set graph;
/// doing that per row per re-render is what made the list unusable.
struct WorkoutCardModel: Identifiable, Hashable, Sendable {
    let id: UUID
    let startTime: Date
    let routineName: String
    let type: WorkoutType
    let durationMinutes: Int
    let completedSets: Int
    let totalVolume: Double
    let completionPercentage: Int
    let prLifts: Int

    var isPR: Bool { prLifts > 0 }
}
