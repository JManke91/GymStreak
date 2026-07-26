//
//  FortschrittListViewModelTests.swift
//  GymStreakTests
//

import Foundation
import Testing
@testable import GymStreak

@MainActor
struct FortschrittListViewModelTests {
    @Test
    func cachesGroupStatisticsAndFlatRows() {
        let model = FortschrittListViewModel()
        model.updateExercises([
            exercise(id: "bench", name: "Bench Press", group: "Chest", count: 8, trend: 10),
            exercise(id: "fly", name: "Cable Fly", group: "Chest", count: 4, trend: 20),
            exercise(id: "squat", name: "Squat", group: "Legs", count: 6, trend: nil)
        ])

        #expect(model.totalCount == 3)
        #expect(model.averageTrend == 15)
        #expect(model.groupStats.map(\.name) == ["Chest", "Legs"])
        #expect(model.rows.count == 5)
    }

    @Test
    func searchAndGroupChangesRebuildCachedRows() {
        let model = FortschrittListViewModel()
        model.updateExercises([
            exercise(id: "bench", name: "Bench Press", group: "Chest", count: 8),
            exercise(id: "fly", name: "Cable Fly", group: "Chest", count: 4),
            exercise(id: "squat", name: "Squat", group: "Legs", count: 6)
        ])

        model.searchText = "bench"
        #expect(exerciseNames(in: model.rows) == ["Bench Press"])

        model.searchText = ""
        model.activeGroup = "Legs"
        #expect(exerciseNames(in: model.rows) == ["Squat"])
    }

    @Test
    func changedValuesWithStableIdentityRefreshNavigationPayload() {
        let model = FortschrittListViewModel()
        let original = exercise(id: "bench", name: "Bench Press", group: "Chest", count: 2)
        model.updateExercises([original])

        let updated = exercise(id: "bench", name: "Bench Press", group: "Chest", count: 9)
        model.updateExercises([updated])

        #expect(model.navigationValue(for: updated).workoutCount == 9)
    }

    private func exercise(
        id: String,
        name: String,
        group: String,
        count: Int,
        trend: Double? = nil
    ) -> FortschrittExerciseModel {
        FortschrittExerciseModel(
            id: id,
            name: name,
            primaryMuscleGroup: group,
            muscleGroups: [group],
            exerciseId: UUID(),
            workoutCount: count,
            lastPerformed: nil,
            trendPct: trend,
            sparkline: []
        )
    }

    private func exerciseNames(
        in rows: [FortschrittListViewModel.Row]
    ) -> [String] {
        rows.compactMap { row in
            guard case .exercise(let exercise) = row else { return nil }
            return exercise.name
        }
    }
}
