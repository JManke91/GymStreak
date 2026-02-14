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
}

// MARK: - Exercise Progress Data Point

struct ExerciseProgressDataPoint: Identifiable {
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

struct ExerciseProgressData {
    let exerciseName: String
    let dataPoints: [ExerciseProgressDataPoint]

    /// Personal record (highest max weight achieved)
    var personalRecord: Double? {
        dataPoints.map(\.maxWeight).max()
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

        return ((lastValue - firstValue) / firstValue) * 100
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

// MARK: - Previous Exercise Performance

struct PreviousExercisePerformance {
    let date: Date
    let routineName: String
    let sets: [SetPerformance]

    struct SetPerformance {
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
    let exerciseName: String
    let currentPerformance: CurrentExercisePerformance
    let previousPerformance: PreviousExercisePerformance?

    struct CurrentExercisePerformance {
        let sets: [SetComparison]
        let totalVolume: Double
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

    /// Volume change compared to previous
    var volumeDelta: Double? {
        guard let previous = previousPerformance else { return nil }
        return currentPerformance.totalVolume - previous.totalVolume
    }

    /// Volume change percentage
    var volumeDeltaPercentage: Double? {
        guard let previous = previousPerformance, previous.totalVolume > 0 else { return nil }
        return ((currentPerformance.totalVolume - previous.totalVolume) / previous.totalVolume) * 100
    }
}
