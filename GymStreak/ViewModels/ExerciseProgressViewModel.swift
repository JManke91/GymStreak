//
//  ExerciseProgressViewModel.swift
//  GymStreak
//

import Foundation
import SwiftData
import SwiftUI

@MainActor
class ExerciseProgressViewModel: ObservableObject {
    @Published var selectedTimeframe: ChartTimeframe = .month
    @Published var selectedMetric: ProgressMetric = .maxWeight
    @Published var progressData: ExerciseProgressData?
    @Published var isLoading = true

    private var exerciseName: String
    private var modelContext: ModelContext?

    init(exerciseName: String) {
        self.exerciseName = exerciseName
    }

    func updateModelContext(_ context: ModelContext) {
        self.modelContext = context
        loadData()
    }

    func updateExercise(_ newExerciseName: String, context: ModelContext) {
        self.exerciseName = newExerciseName
        self.modelContext = context
        loadData()
    }

    func loadData() {
        guard let context = modelContext else { return }

        isLoading = true
        let service = ExerciseProgressService(modelContext: context)
        progressData = service.fetchProgressData(for: exerciseName, timeframe: selectedTimeframe)
        isLoading = false
    }

    func updateTimeframe(_ timeframe: ChartTimeframe) {
        selectedTimeframe = timeframe
        loadData()
    }

    func updateMetric(_ metric: ProgressMetric) {
        selectedMetric = metric
    }

    // MARK: - Computed Properties for Display

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
