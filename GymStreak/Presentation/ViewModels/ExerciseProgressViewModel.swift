//
//  ExerciseProgressViewModel.swift
//  GymStreak
//

import Foundation
import SwiftUI

@MainActor
class ExerciseProgressViewModel: ObservableObject {
    @Published var selectedTimeframe: ChartTimeframe = .month
    @Published var selectedMetric: ProgressMetric = .maxWeight
    @Published var progressData: ExerciseProgressData?
    @Published var selectedDataPoint: SelectedDataPoint?
    @Published var isLoading = true

    private var exerciseName: String
    private var exerciseId: UUID?
    private let progressService: ExerciseProgressProviding

    init(exerciseName: String, exerciseId: UUID? = nil, progressService: ExerciseProgressProviding) {
        self.exerciseName = exerciseName
        self.exerciseId = exerciseId
        self.progressService = progressService
        loadData()
    }

    func updateExercise(_ newExerciseName: String, exerciseId: UUID?) {
        self.exerciseName = newExerciseName
        self.exerciseId = exerciseId
        selectedDataPoint = nil
        loadData()
    }

    func loadData() {
        isLoading = true
        progressData = progressService.fetchProgressData(for: exerciseName, exerciseId: exerciseId, timeframe: selectedTimeframe)
        if !availableMetrics.contains(selectedMetric) {
            selectedMetric = .maxWeight
        }
        isLoading = false
    }

    func updateTimeframe(_ timeframe: ChartTimeframe) {
        selectedTimeframe = timeframe
        selectedDataPoint = nil
        loadData()
    }

    func updateMetric(_ metric: ProgressMetric) {
        guard availableMetrics.contains(metric) else { return }
        selectedMetric = metric
        selectedDataPoint = nil
    }

    // MARK: - Data Point Selection

    func selectDataPoint(_ dataPoint: ExerciseProgressDataPoint, for metric: ProgressMetric) {
        let value = dataPoint.value(for: metric)
        let displayValue = formatCompactValue(value, unit: metric.unit)
        let displayDate = dataPoint.date.formatted(date: .abbreviated, time: .omitted)
        selectedDataPoint = SelectedDataPoint(
            dataPoint: dataPoint,
            displayValue: displayValue,
            displayDate: displayDate
        )
    }

    func clearSelection() {
        selectedDataPoint = nil
    }

    // MARK: - Computed Properties for Display

    var availableMetrics: [ProgressMetric] {
        guard let data = progressData,
              data.loadBehavior.isCounterweightAssistance,
              !data.usesEffectiveLoad else {
            return ProgressMetric.allCases
        }
        return [.maxWeight]
    }

    var selectedMetricTitle: String {
        guard selectedMetric == .maxWeight,
              progressData?.loadBehavior.isCounterweightAssistance == true,
              progressData?.usesEffectiveLoad == false else {
            return selectedMetric.localizedTitle
        }
        return "exercise.assistance".localized
    }

    var personalRecordString: String? {
        guard let data = progressData else { return nil }

        switch selectedMetric {
        case .maxWeight:
            if let pr = data.personalRecord {
                return String(format: "%.1f kg", pr)
            }
        case .estimated1RM:
            if let pr = data.personalRecord1RM {
                return String(format: "%.1f kg", pr)
            }
        case .volume:
            if let maxVolume = data.dataPoints.map(\.totalVolume).max() {
                return String(format: "%.0f kg", maxVolume)
            }
        }
        return nil
    }

    var trendPercentageString: String? {
        guard let percentage = progressData?.progressPercentage(for: selectedMetric) else {
            return nil
        }

        let sign = percentage >= 0 ? "+" : ""
        return String(format: "%@%.1f%%", sign, percentage)
    }

    var trendIsPositive: Bool {
        guard let percentage = progressData?.progressPercentage(for: selectedMetric) else {
            return false
        }
        return percentage >= 0
    }

    var sessionCountString: String? {
        guard let count = progressData?.sessionCount else { return nil }
        return "\(count)"
    }
}
