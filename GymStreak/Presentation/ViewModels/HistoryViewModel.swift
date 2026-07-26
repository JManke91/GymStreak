//
//  HistoryViewModel.swift
//  GymStreak
//

import Foundation
import Observation
import OSLog

/// Owns the precomputed History screen state.
///
/// The Trainings tab used to derive everything it rendered inside `body`, and `HistoryView.refresh()`
/// ran two whole-history aggregations synchronously up to three times per appearance. This type
/// exists so that work happens **once per meaningful change** instead, behind a single `.task(id:)`.
///
/// `@Observable` (not `ObservableObject`) on purpose: with `@Published`, any one of a view model's
/// properties changing invalidates every view holding it, whereas `@Observable` tracks the
/// properties a `body` actually reads. Its injected provider is a Data-layer `@ModelActor`, so the
/// main actor only publishes immutable snapshots and never performs history fetches or aggregation.
@Observable
@MainActor
final class HistoryViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed
    }

    /// The Trainings tab's rows and header values.
    private(set) var snapshot: HistorySnapshot = .empty
    /// The Fortschritt tab's rows. Built only while that tab is the visible one.
    let fortschrittList = FortschrittListViewModel()
    private(set) var loadState: LoadState = .loading
    private(set) var isLoadingFortschritt = false
    private(set) var didFailFortschritt = false

    private let provider: HistorySnapshotProviding
    private let signposter = OSSignposter(
        subsystem: "com.shotat24fps.GymStreak",
        category: "History"
    )
    private var trainingGeneration = 0
    private var fortschrittGeneration = 0

    init(provider: HistorySnapshotProviding) {
        self.provider = provider
    }

    var hasLoaded: Bool { loadState == .loaded }
    var didFailLoading: Bool { loadState == .failed }

    /// Fetches and builds Trainings away from MainActor. Generation checks are separate from task
    /// cancellation because SwiftData fetches are synchronous inside the model actor: an older
    /// request can finish after a newer notification and must never overwrite newer state.
    @discardableResult
    func reloadTraining(referenceDate: Date = Date()) async -> Bool {
        trainingGeneration += 1
        let generation = trainingGeneration
        if snapshot.sessionCount == 0 {
            loadState = .loading
        }

        do {
            let result = try await provider.fetchTrainingSnapshot(referenceDate: referenceDate)
            guard !Task.isCancelled, generation == trainingGeneration else { return false }
            snapshot = result
            loadState = .loaded
            signposter.emitEvent("HistorySnapshotPublished")
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard generation == trainingGeneration else { return false }
            loadState = .failed
            return false
        }
    }

    func reloadFortschritt() async {
        fortschrittGeneration += 1
        let generation = fortschrittGeneration
        isLoadingFortschritt = true
        didFailFortschritt = false

        do {
            let result = try await provider.fetchFortschrittSnapshot()
            guard !Task.isCancelled, generation == fortschrittGeneration else { return }
            fortschrittList.updateExercises(result)
            isLoadingFortschritt = false
            signposter.emitEvent("HistoryFortschrittPublished")
        } catch is CancellationError {
            guard generation == fortschrittGeneration else { return }
            isLoadingFortschritt = false
        } catch {
            guard generation == fortschrittGeneration else { return }
            isLoadingFortschritt = false
            didFailFortschritt = true
        }
    }
}

/// Cached presentation projection for Fortschritt's search/filter/list UI.
///
/// The actor-owned provider already performs the expensive history aggregation. This second,
/// main-actor cache ensures SwiftUI's render path only reads stable values instead of repeatedly
/// mapping, grouping, filtering, sorting and reducing the full exercise list.
@Observable
@MainActor
final class FortschrittListViewModel {
    struct GroupStat: Identifiable {
        let name: String
        let total: Int
        let avgTrend: Double?

        var id: String { name }
    }

    enum Row: Identifiable {
        case header(String, Int)
        case exercise(FortschrittExerciseModel)

        var id: String {
            switch self {
            case .header(let group, _): return "header-\(group)"
            case .exercise(let model): return "row-\(model.id)"
            }
        }
    }

    static let allGroupId = "all"

    var searchText = "" {
        didSet { rebuildRows() }
    }
    var activeGroup = allGroupId {
        didSet { rebuildRows() }
    }

    private(set) var totalCount = 0
    private(set) var averageTrend: Double?
    private(set) var groupStats: [GroupStat] = []
    private(set) var rows: [Row] = []

    private var exercises: [FortschrittExerciseModel] = []
    private var allExercisesForNavigation: [ExerciseWithHistory] = []

    func updateExercises(_ exercises: [FortschrittExerciseModel]) {
        guard self.exercises != exercises else { return }
        self.exercises = exercises
        totalCount = exercises.count
        allExercisesForNavigation = exercises.map(Self.navigationModel)

        let trends = exercises.compactMap(\.trendPct)
        averageTrend = trends.isEmpty ? nil : trends.reduce(0, +) / Double(trends.count)

        groupStats = Dictionary(grouping: exercises, by: \.primaryMuscleGroup)
            .map { key, items in
                let trends = items.compactMap(\.trendPct)
                return GroupStat(
                    name: key,
                    total: items.count,
                    avgTrend: trends.isEmpty ? nil : trends.reduce(0, +) / Double(trends.count)
                )
            }
            .sorted { $0.name < $1.name }

        if activeGroup != Self.allGroupId,
           !groupStats.contains(where: { $0.name == activeGroup }) {
            activeGroup = Self.allGroupId
        } else {
            rebuildRows()
        }
    }

    func navigationValue(for exercise: FortschrittExerciseModel) -> ExerciseWithHistory {
        var value = Self.navigationModel(exercise)
        value.allExercises = allExercisesForNavigation
        return value
    }

    private func rebuildRows() {
        let filtered = exercises
            .filter { exercise in
                searchText.isEmpty
                    || exercise.name.localizedCaseInsensitiveContains(searchText)
                    || exercise.muscleGroups.contains {
                        $0.localizedCaseInsensitiveContains(searchText)
                    }
            }
            .filter {
                activeGroup == Self.allGroupId || $0.primaryMuscleGroup == activeGroup
            }

        rows = Dictionary(grouping: filtered, by: \.primaryMuscleGroup)
            .map { group, items in
                (group, items.sorted { $0.workoutCount > $1.workoutCount })
            }
            .sorted { $0.0 < $1.0 }
            .flatMap { group, items in
                [.header(group, items.count)] + items.map { .exercise($0) }
            }
    }

    private static func navigationModel(
        _ exercise: FortschrittExerciseModel
    ) -> ExerciseWithHistory {
        ExerciseWithHistory(
            name: exercise.name,
            muscleGroups: exercise.muscleGroups,
            exerciseId: exercise.exerciseId,
            workoutCount: exercise.workoutCount,
            lastPerformed: exercise.lastPerformed
        )
    }
}

/// Which History sub-tab is showing. Top-level rather than nested in the view so the view model
/// can name it without depending on a `View` type.
enum HistorySection: String, CaseIterable {
    case trainings, fortschritt

    var title: String {
        switch self {
        case .trainings:    return "history.mode.workouts".localized
        case .fortschritt:  return "history.mode.progress".localized
        }
    }
}
