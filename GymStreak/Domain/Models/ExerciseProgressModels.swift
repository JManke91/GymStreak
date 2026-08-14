//
//  ExerciseProgressModels.swift
//  GymStreak
//

import Foundation

// Note: String+Localization.swift extension provides .localized property

// MARK: - Chart Timeframe

enum ChartTimeframe: String, CaseIterable, Identifiable {
    case week = "1W"
    case month = "1M"
    case threeMonths = "3M"
    case year = "1Y"
    case all = "All"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .week: return "chart.timeframe.week".localized
        case .month: return "chart.timeframe.month".localized
        case .threeMonths: return "chart.timeframe.three_months".localized
        case .year: return "chart.timeframe.year".localized
        case .all: return "chart.timeframe.all".localized
        }
    }

    var axisStrideComponent: Calendar.Component {
        switch self {
        case .week: return .day
        case .month: return .weekOfYear
        case .threeMonths: return .month
        case .year: return .month
        case .all: return .month
        }
    }

    var axisStrideValue: Int {
        switch self {
        case .week: return 1
        case .month: return 1
        case .threeMonths: return 1
        case .year: return 2
        case .all: return 3
        }
    }

    var startDate: Date {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .week:
            return calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .month:
            return calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .threeMonths:
            return calendar.date(byAdding: .month, value: -3, to: now) ?? now
        case .year:
            return calendar.date(byAdding: .year, value: -1, to: now) ?? now
        case .all:
            return Date.distantPast
        }
    }
}

// MARK: - Progress Metric

enum ProgressMetric: String, CaseIterable, Identifiable {
    case maxWeight
    case estimated1RM
    case volume

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .maxWeight: return "chart.metric.max_weight".localized
        case .estimated1RM: return "chart.metric.estimated_1rm".localized
        case .volume: return "chart.metric.volume".localized
        }
    }

    var unit: String {
        switch self {
        case .maxWeight, .estimated1RM: return "kg"
        case .volume: return "kg"
        }
    }

    var localizedDescription: String {
        switch self {
        case .maxWeight: return "chart.metric.max_weight.description".localized
        case .estimated1RM: return "chart.metric.estimated_1rm.description".localized
        case .volume: return "chart.metric.volume.description".localized
        }
    }
}

// MARK: - Compact Number Formatting

/// Formats a number using compact notation (e.g., 1.2k, 3.5M) with optional unit suffix
func formatCompactValue(_ value: Double, unit: String? = nil) -> String {
    let formatted: String
    switch abs(value) {
    case 0..<1:
        formatted = String(format: "%.1f", value)
    case 1..<1_000:
        formatted = String(format: "%.0f", value)
    case 1_000..<1_000_000:
        let k = value / 1_000
        formatted = k.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0fk", k)
            : String(format: "%.1fk", k)
    default:
        let m = value / 1_000_000
        formatted = m.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0fM", m)
            : String(format: "%.1fM", m)
    }
    if let unit {
        return "\(formatted) \(unit)"
    }
    return formatted
}

// MARK: - Exercise Progress Data Point

struct ExerciseProgressDataPoint: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let maxWeight: Double
    let estimated1RM: Double
    let totalVolume: Double
    let totalSets: Int
    let totalReps: Int
    let workoutSessionId: UUID

    /// Get the value for a specific metric
    func value(for metric: ProgressMetric) -> Double {
        switch metric {
        case .maxWeight: return maxWeight
        case .estimated1RM: return estimated1RM
        case .volume: return totalVolume
        }
    }
}

// MARK: - Exercise Progress Data

struct ExerciseProgressData: Sendable {
    let exerciseName: String
    let dataPoints: [ExerciseProgressDataPoint]
    let loadBehavior: ExerciseLoadBehavior
    /// Assistance workouts only expose effective-load strength metrics when
    /// every point has a stored body-mass snapshot.
    let usesEffectiveLoad: Bool

    init(
        exerciseName: String,
        dataPoints: [ExerciseProgressDataPoint],
        loadBehavior: ExerciseLoadBehavior = .resistance,
        usesEffectiveLoad: Bool = false
    ) {
        self.exerciseName = exerciseName
        self.dataPoints = dataPoints
        self.loadBehavior = loadBehavior
        self.usesEffectiveLoad = usesEffectiveLoad
    }

    /// Personal record (highest max weight achieved)
    var personalRecord: Double? {
        loadBehavior.isCounterweightAssistance && !usesEffectiveLoad
            ? dataPoints.map(\.maxWeight).min()
            : dataPoints.map(\.maxWeight).max()
    }

    /// Personal record for estimated 1RM
    var personalRecord1RM: Double? {
        dataPoints.map(\.estimated1RM).max()
    }

    /// Progress percentage comparing first and last data points for a given metric
    func progressPercentage(for metric: ProgressMetric) -> Double? {
        guard dataPoints.count >= 2,
              let first = dataPoints.first,
              let last = dataPoints.last else {
            return nil
        }

        let firstValue = first.value(for: metric)
        let lastValue = last.value(for: metric)

        guard firstValue > 0 else { return nil }

        let delta = loadBehavior.isCounterweightAssistance && !usesEffectiveLoad
            ? firstValue - lastValue
            : lastValue - firstValue
        return (delta / firstValue) * 100
    }

    /// Total number of sessions/workouts
    var sessionCount: Int {
        dataPoints.count
    }

    /// Check if there's enough data to show a chart
    var hasEnoughData: Bool {
        dataPoints.count >= 1
    }

    /// Check if there's enough data to show a trend
    var hasEnoughDataForTrend: Bool {
        dataPoints.count >= 2
    }
}

// MARK: - Exercise Recent Session

/// One row of the exercise detail's "recent sessions" list.
///
/// A denormalized value, not a `WorkoutSession`: it is built inside
/// `SwiftDataHistorySnapshotStore`'s model actor and crosses back to the main
/// actor, so no `PersistentModel` and no relationship walk may survive in it.
struct ExerciseRecentSession: Identifiable, Sendable {
    /// The originating `WorkoutSession.id` — stable across reloads, unlike a minted UUID.
    let id: UUID
    let date: Date
    let sets: [SetEntry]

    struct SetEntry: Identifiable, Sendable {
        let id: UUID
        let weight: Double
        let reps: Int
    }

    var bestSet: SetEntry? {
        sets.max(by: { $0.weight < $1.weight })
    }
}

// MARK: - Exercise Progress Snapshot

/// Everything the exercise detail screen renders, built in a single pass over one
/// prefetched session graph.
///
/// The chart series and the recent-session list are returned together deliberately:
/// they read the same fetch, and shipping them as two boundary calls would mean two
/// unbounded fetches plus a chance for the two halves of one screen to disagree.
struct ExerciseProgressSnapshot: Sendable {
    let data: ExerciseProgressData
    let recentSessions: [ExerciseRecentSession]
}

// MARK: - Selected Data Point

struct SelectedDataPoint {
    let dataPoint: ExerciseProgressDataPoint
    let displayValue: String
    let displayDate: String
}

// MARK: - Previous Exercise Performance

/// What the user did the last comparable time they performed one exercise.
///
/// `Sendable` because it is resolved inside `SwiftDataHistorySnapshotStore`'s model actor
/// and crosses back to the main actor (audit P1.6) — no `PersistentModel` and no
/// relationship walk may survive in it.
struct PreviousExercisePerformance: Sendable {
    let date: Date
    let routineName: String
    let sets: [SetPerformance]
    let effectiveTotalVolume: Double?

    struct SetPerformance: Sendable {
        let reps: Int
        let weight: Double
        let isCompleted: Bool
    }

    /// Best set by weight from the previous workout
    var bestSet: SetPerformance? {
        sets.filter(\.isCompleted).max(by: { $0.weight < $1.weight })
    }

    /// Total volume from the previous workout
    var totalVolume: Double {
        sets.filter(\.isCompleted).reduce(0) { $0 + ($1.weight * Double($1.reps)) }
    }

    /// Total completed sets
    var completedSetsCount: Int {
        sets.filter(\.isCompleted).count
    }

    /// Total reps from completed sets
    var totalReps: Int {
        sets.filter(\.isCompleted).reduce(0) { $0 + $1.reps }
    }
}

// MARK: - Exercise Comparison Result

struct ExerciseComparisonResult {
    /// The `WorkoutExercise.id` this row describes.
    ///
    /// Callers used to pair results with exercises **positionally** (a `zip`, or an
    /// index into the results array), which silently mispairs the moment the two
    /// orderings diverge, and cannot key a `ForEach` for a workout that contains the
    /// same exercise twice. Carrying the id makes the pairing explicit.
    let workoutExerciseId: UUID
    let exerciseName: String
    let loadBehavior: ExerciseLoadBehavior
    let currentPerformance: CurrentExercisePerformance
    let previousPerformance: PreviousExercisePerformance?

    struct CurrentExercisePerformance {
        let sets: [SetComparison]
        let totalVolume: Double
        let effectiveTotalVolume: Double?
        let completedSetsCount: Int
        let totalReps: Int

        struct SetComparison {
            let setNumber: Int
            let currentReps: Int
            let currentWeight: Double
            let previousReps: Int?
            let previousWeight: Double?
            let isCompleted: Bool

            var repsDelta: Int? {
                guard let previous = previousReps else { return nil }
                return currentReps - previous
            }

            var weightDelta: Double? {
                guard let previous = previousWeight else { return nil }
                return currentWeight - previous
            }
        }
    }

    /// Whether this is the first time performing this exercise
    var isFirstTime: Bool {
        previousPerformance == nil
    }

    var hasComparableVolume: Bool {
        guard let previousPerformance else { return false }
        return currentPerformance.effectiveTotalVolume != nil && previousPerformance.effectiveTotalVolume != nil
    }

    /// Volume change compared to previous
    var volumeDelta: Double? {
        guard let previous = previousPerformance,
              let currentVolume = currentPerformance.effectiveTotalVolume,
              let previousVolume = previous.effectiveTotalVolume else { return nil }
        return currentVolume - previousVolume
    }

    /// Volume change percentage
    var volumeDeltaPercentage: Double? {
        guard let previous = previousPerformance,
              let currentVolume = currentPerformance.effectiveTotalVolume,
              let previousVolume = previous.effectiveTotalVolume,
              previousVolume > 0 else { return nil }
        return ((currentVolume - previousVolume) / previousVolume) * 100
    }
}
