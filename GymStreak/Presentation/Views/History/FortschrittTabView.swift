//
//  FortschrittTabView.swift
//  GymStreak
//

import SwiftUI

/// The Fortschritt (Progress) sub-tab: search + muscle-group pills + grouped exercise rows.
struct FortschrittTabView: View {
    let exercises: [FortschrittExerciseModel]
    let allExerciseNames: [String]

    @State private var searchText = ""
    @State private var activeGroup: String = "all"

    /// Precomputed "all exercises with history" payload, reused for every row's NavigationLink.
    private var allExercisesForNavigation: [ExerciseWithHistory] {
        exercises.map {
            ExerciseWithHistory(
                name: $0.name,
                muscleGroups: $0.muscleGroups,
                exerciseId: $0.exerciseId,
                workoutCount: $0.workoutCount,
                lastPerformed: $0.lastPerformed
            )
        }
    }

    private let allGroupId = "all"

    private var groupStats: [GroupStat] {
        let grouped = Dictionary(grouping: exercises) { $0.primaryMuscleGroup }
        return grouped.map { key, items in
            let trend = items.compactMap(\.trendPct)
            let avg = trend.isEmpty ? nil : trend.reduce(0, +) / Double(trend.count)
            return GroupStat(name: key, total: items.count, avgTrend: avg)
        }
        .sorted { $0.name < $1.name }
    }

    private var filteredExercises: [FortschrittExerciseModel] {
        exercises
            .filter { model in
                searchText.isEmpty ||
                model.name.localizedCaseInsensitiveContains(searchText) ||
                model.muscleGroups.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
            .filter { activeGroup == allGroupId || $0.primaryMuscleGroup == activeGroup }
    }

    private var grouped: [(String, [FortschrittExerciseModel])] {
        Dictionary(grouping: filteredExercises, by: \.primaryMuscleGroup)
            .map { ($0.key, $0.value.sorted { $0.workoutCount > $1.workoutCount }) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            searchBar
            pills
            content
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.5))
            TextField(
                "",
                text: $searchText,
                prompt: Text("progress.search".localized)
                    .foregroundStyle(Color.white.opacity(0.4))
            )
            .font(.system(size: 14))
            .foregroundStyle(Color.white)
            .tint(DesignSystem.Colors.tint)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }

    // MARK: - Muscle group pills

    private var pills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                MusclePillView(
                    title: "history.group.all".localized,
                    subtitle: "history.group.count".localized(exercises.count),
                    trend: averageTrend(),
                    isActive: activeGroup == allGroupId
                ) {
                    HapticManager.shared.selection()
                    activeGroup = allGroupId
                }
                ForEach(groupStats, id: \.name) { stat in
                    MusclePillView(
                        title: stat.name.localized,
                        subtitle: "history.group.count".localized(stat.total),
                        trend: stat.avgTrend,
                        isActive: activeGroup == stat.name
                    ) {
                        HapticManager.shared.selection()
                        activeGroup = stat.name
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if exercises.isEmpty {
            ContentUnavailableView {
                Label("progress.empty.title".localized, systemImage: "chart.line.uptrend.xyaxis")
            } description: {
                Text("progress.empty.description".localized)
            }
            .padding(.top, 30)
        } else if filteredExercises.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .padding(.top, 30)
        } else {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(grouped, id: \.0) { group, items in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(group.localized)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .kerning(-0.3)
                                .foregroundStyle(Color.white)
                            Spacer()
                            Text("history.group.count".localized(items.count))
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.4))
                        }
                        .padding(.horizontal, 20)
                        VStack(spacing: 8) {
                            ForEach(items) { model in
                                NavigationLink(value: navigationValue(for: model)) {
                                    FortschrittExerciseRowView(model: model)
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(TapGesture().onEnded { HapticManager.shared.light() })
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    private func averageTrend() -> Double? {
        let trends = exercises.compactMap(\.trendPct)
        return trends.isEmpty ? nil : trends.reduce(0, +) / Double(trends.count)
    }

    private func navigationValue(for model: FortschrittExerciseModel) -> ExerciseWithHistory {
        var value = ExerciseWithHistory(
            name: model.name,
            muscleGroups: model.muscleGroups,
            exerciseId: model.exerciseId,
            workoutCount: model.workoutCount,
            lastPerformed: model.lastPerformed
        )
        value.allExercises = allExercisesForNavigation
        return value
    }

    struct GroupStat {
        let name: String
        let total: Int
        let avgTrend: Double?
    }
}
