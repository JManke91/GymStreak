//
//  ExerciseProgressViewModel.swift
//  GymStreak
//

import Foundation
import SwiftUI

/// Owns the exercise detail screen's precomputed state.
///
/// Loading is `async` on purpose (audit P1.2). It used to be a synchronous
/// `fetchProgressData` call with no `await` anywhere in the chain, run from `init` and
/// again on every range-pill tap and exercise switch: an unbounded fetch plus a full
/// relationship traversal, on the main actor, for every user with a chart — the same
/// shape that measured ~600 ms in History. The work now happens inside
/// `SwiftDataHistorySnapshotStore`'s model actor and only immutable values come back.
/// `isLoading` is also observable for the first time; nothing used to yield, so the
/// spinner could never render.
@MainActor
class ExerciseProgressViewModel: ObservableObject {
    /// Identity of a load. `ExerciseProgressChartView` feeds this to `.task(id:)`, which
    /// cancels and restarts the load whenever the exercise or the timeframe changes.
    struct LoadKey: Equatable {
        let exerciseName: String
        let exerciseId: UUID?
        let timeframe: ChartTimeframe
    }

    @Published var selectedTimeframe: ChartTimeframe = .month
    @Published var selectedMetric: ProgressMetric = .maxWeight
    @Published private(set) var progressData: ExerciseProgressData?
    @Published private(set) var recentSessions: [ExerciseRecentSession] = []
    @Published var selectedDataPoint: SelectedDataPoint?
    @Published private(set) var isLoading = true

    /// Bounded so the recent-session list stays a fixed-size, non-lazy stack.
    static let recentSessionLimit = 8

    private var exerciseName: String
    private var exerciseId: UUID?
    private let provider: HistorySnapshotProviding

    /// Separate from task cancellation on purpose, mirroring `HistoryViewModel`: the
    /// fetches inside the model actor are synchronous, so a superseded load can still
    /// run to completion and resume here after a newer one has already published. Only
    /// the newest generation is allowed to write.
    private var generation = 0

    init(exerciseName: String, exerciseId: UUID? = nil, provider: HistorySnapshotProviding) {
        self.exerciseName = exerciseName
        self.exerciseId = exerciseId
        self.provider = provider
    }

    var loadKey: LoadKey {
        LoadKey(exerciseName: exerciseName, exerciseId: exerciseId, timeframe: selectedTimeframe)
    }

    /// Mutates the load parameters only — `.task(id: viewModel.loadKey)` performs the reload.
    func updateExercise(_ newExerciseName: String, exerciseId: UUID?) {
        self.exerciseName = newExerciseName
        self.exerciseId = exerciseId
        selectedDataPoint = nil
    }

    func updateTimeframe(_ timeframe: ChartTimeframe) {
        selectedTimeframe = timeframe
        selectedDataPoint = nil
    }

    func load() async {
        generation += 1
        let generation = self.generation
        isLoading = true

        // Resolved here, not inside the actor: `ChartTimeframe.startDate` reads
        // `Calendar.current` and `Date()`, so only the resulting cutoff crosses the hop.
        let startDate = selectedTimeframe.startDate

        do {
            let snapshot = try await provider.fetchExerciseProgress(
                exerciseName: exerciseName,
                exerciseId: exerciseId,
                startDate: startDate,
                recentSessionLimit: Self.recentSessionLimit
            )
            guard !Task.isCancelled, generation == self.generation else { return }
            progressData = snapshot.data
            recentSessions = snapshot.recentSessions
            if !availableMetrics.contains(selectedMetric) {
                selectedMetric = .maxWeight
            }
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            guard generation == self.generation else { return }
            progressData = nil
            recentSessions = []
            isLoading = false
        }
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
