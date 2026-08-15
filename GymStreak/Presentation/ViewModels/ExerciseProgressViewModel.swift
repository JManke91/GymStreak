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

    /// The last window this user was actually allowed to read. It is what the
    /// chart keeps drawing while a Pro-only window is selected — see
    /// `chartTimeframe`.
    @Published private(set) var lastUnlockedTimeframe: ChartTimeframe = .month

    /// Bounded so the recent-session list stays a fixed-size, non-lazy stack.
    static let recentSessionLimit = 8

    private var exerciseName: String
    private var exerciseId: UUID?
    private let provider: HistorySnapshotProviding
    private let proEntitlements: any ProEntitlementProviding
    private let paywalls: any PaywallPresenting
    private let isGatingEnabled: Bool

    /// Separate from task cancellation on purpose, mirroring `HistoryViewModel`: the
    /// fetches inside the model actor are synchronous, so a superseded load can still
    /// run to completion and resume here after a newer one has already published. Only
    /// the newest generation is allowed to write.
    private var generation = 0

    /// - Parameter isGatingEnabled: injected rather than read from `ProGating`
    ///   inside the gate, for the same reason `PaywallPresenter` and
    ///   `RoutinesViewModel` inject it: the shipped switch is off, so a test
    ///   baking it in would prove the gate is inert rather than correct.
    init(
        exerciseName: String,
        exerciseId: UUID? = nil,
        provider: HistorySnapshotProviding,
        proEntitlements: any ProEntitlementProviding,
        paywalls: any PaywallPresenting,
        isGatingEnabled: Bool = ProGating.isEnabled
    ) {
        self.exerciseName = exerciseName
        self.exerciseId = exerciseId
        self.provider = provider
        self.proEntitlements = proEntitlements
        self.paywalls = paywalls
        self.isGatingEnabled = isGatingEnabled
    }

    /// Keyed on `chartTimeframe`, not on the selection: picking a Pro-only
    /// window must not widen the fetch just so the result can be blurred.
    var loadKey: LoadKey {
        LoadKey(exerciseName: exerciseName, exerciseId: exerciseId, timeframe: chartTimeframe)
    }

    /// Mutates the load parameters only — `.task(id: viewModel.loadKey)` performs the reload.
    func updateExercise(_ newExerciseName: String, exerciseId: UUID?) {
        self.exerciseName = newExerciseName
        self.exerciseId = exerciseId
        selectedDataPoint = nil
    }

    /// Selects a window. A Pro-only one is still *selected* — its pill highlights
    /// and the chart blurs behind the lock — but it raises `chartWindow` and
    /// leaves the loaded window alone.
    func updateTimeframe(_ timeframe: ChartTimeframe) {
        selectedTimeframe = timeframe
        selectedDataPoint = nil
        if isTimeframeLocked(timeframe) {
            paywalls.present(.chartWindow)
        } else {
            lastUnlockedTimeframe = timeframe
        }
    }

    func load() async {
        generation += 1
        let generation = self.generation
        isLoading = true

        // Resolved here, not inside the actor: `ChartTimeframe.startDate` reads
        // `Calendar.current` and `Date()`, so only the resulting cutoff crosses the hop.
        // `chartTimeframe`, not the selection: a Pro-only window never widens the fetch.
        let startDate = chartTimeframe.startDate

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

    /// Selects a metric. A Pro-only one is still *selected* — the tab highlights
    /// and its real series renders blurred behind the lock — but it raises
    /// `chartMetric`. Nothing extra is computed for it: every data point already
    /// carries all three values from the one fetch.
    func updateMetric(_ metric: ProgressMetric) {
        guard availableMetrics.contains(metric) else { return }
        selectedMetric = metric
        selectedDataPoint = nil
        if isMetricLocked(metric) {
            paywalls.present(.chartMetric)
        }
    }

    // MARK: - Progress analytics gate (P2)
    //
    // The rules live in `ChartGatingPolicy`; this end owns only the inputs (the
    // live entitlement) and what a locked selection does to the screen. The gate
    // narrows the *analytics view* and nothing else — no session, set or workout
    // is hidden in any entitlement state, and a resubscribe restores the full
    // window on the spot because nothing was ever migrated away.

    /// `true` when this metric is Pro-only for the current user.
    ///
    /// Computed rather than stored so it tracks the entitlement live:
    /// `proEntitlements` is `@Observable`, and reading it during the chart's
    /// `body` evaluation is what unblurs the screen the moment a purchase lands.
    /// It is a comparison against one constant — no collection walk, no
    /// formatter, no SwiftData read.
    func isMetricLocked(_ metric: ProgressMetric) -> Bool {
        ChartGatingPolicy.isMetricLocked(
            metric,
            isPro: proEntitlements.isPro,
            isGatingEnabled: isGatingEnabled
        )
    }

    /// `true` when this window is Pro-only for the current user.
    func isTimeframeLocked(_ timeframe: ChartTimeframe) -> Bool {
        ChartGatingPolicy.isTimeframeLocked(
            timeframe,
            isPro: proEntitlements.isPro,
            isGatingEnabled: isGatingEnabled
        )
    }

    /// The window the chart actually renders: the selection, or the last
    /// unlocked one while a Pro-only window is selected.
    ///
    /// This is the whole reason a locked window costs nothing — the blurred
    /// preview is the user's own real data over the window they are entitled to,
    /// never a year-long series fetched purely to be made unreadable. It falls
    /// back to the selection once the gate lifts, which is what reloads the full
    /// window on a purchase without any refresh gesture.
    ///
    /// After a lapse the last unlocked window can itself be Pro-only (it was
    /// picked while entitled), so it is clamped to the widest free one rather
    /// than left fetching a year of history for a blur.
    var chartTimeframe: ChartTimeframe {
        guard isTimeframeLocked(selectedTimeframe) else { return selectedTimeframe }
        return isTimeframeLocked(lastUnlockedTimeframe)
            ? ChartGatingPolicy.widestFreeTimeframe()
            : lastUnlockedTimeframe
    }

    /// `true` when the current selection puts the chart behind the Pro lock.
    var isChartLocked: Bool {
        isMetricLocked(selectedMetric) || isTimeframeLocked(selectedTimeframe)
    }

    /// Which capability the lock card names. The metric wins when both are
    /// locked: it is the axis the user just switched, and §8 C only requires the
    /// paywall to name *a* specific capability, not to enumerate them.
    /// Meaningful only while `isChartLocked`.
    var chartLockPlacement: PaywallPlacement {
        isMetricLocked(selectedMetric) ? .chartMetric : .chartWindow
    }

    /// The lock card's CTA.
    func requestChartUnlock() {
        paywalls.present(chartLockPlacement)
    }

    /// The metric the (unblurred) stat triple reports on.
    ///
    /// A locked selection falls back to the free metric so the PR and trend
    /// cards never print a Pro number in plain text beside the blurred chart.
    /// For a free user on a free selection this is simply the selection, i.e.
    /// unchanged from before the gate existed.
    private var statMetric: ProgressMetric {
        isMetricLocked(selectedMetric) ? ProFeatureCaps.freeChartMetric : selectedMetric
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

        switch statMetric {
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
        guard let percentage = progressData?.progressPercentage(for: statMetric) else {
            return nil
        }

        let sign = percentage >= 0 ? "+" : ""
        return String(format: "%@%.1f%%", sign, percentage)
    }

    var trendIsPositive: Bool {
        guard let percentage = progressData?.progressPercentage(for: statMetric) else {
            return false
        }
        return percentage >= 0
    }

    var sessionCountString: String? {
        guard let count = progressData?.sessionCount else { return nil }
        return "\(count)"
    }
}
