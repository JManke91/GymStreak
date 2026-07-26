//
//  FortschrittTabView.swift
//  GymStreak
//

import SwiftUI

/// The Fortschritt (Progress) sub-tab: search + muscle-group pills + grouped exercise rows.
struct FortschrittTabView: View {
    @Bindable var model: FortschrittListViewModel
    let isLoading: Bool
    let didFailLoading: Bool
    let onRetry: () -> Void

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
                text: $model.searchText,
                prompt: Text("progress.search".localized)
                    .foregroundStyle(Color.white.opacity(0.4))
            )
            .font(.system(size: 14))
            .foregroundStyle(Color.white)
            .tint(DesignSystem.Colors.tint)
            if !model.searchText.isEmpty {
                Button { model.searchText = "" } label: {
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
                    subtitle: "history.group.count".localized(model.totalCount),
                    trend: model.averageTrend,
                    isActive: model.activeGroup == FortschrittListViewModel.allGroupId
                ) {
                    HapticManager.shared.selection()
                    model.activeGroup = FortschrittListViewModel.allGroupId
                }
                ForEach(model.groupStats) { stat in
                    MusclePillView(
                        title: stat.name.localized,
                        subtitle: "history.group.count".localized(stat.total),
                        trend: stat.avgTrend,
                        isActive: model.activeGroup == stat.name
                    ) {
                        HapticManager.shared.selection()
                        model.activeGroup = stat.name
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading && model.totalCount == 0 {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else if didFailLoading {
            ContentUnavailableView {
                Label("history.load_error.title".localized, systemImage: "exclamationmark.triangle")
            } description: {
                Text("history.load_error.description".localized)
            } actions: {
                Button("action.try_again".localized, action: onRetry)
                    .buttonStyle(.bordered)
            }
            .padding(.top, 30)
        } else if model.totalCount == 0 {
            ContentUnavailableView {
                Label("progress.empty.title".localized, systemImage: "chart.line.uptrend.xyaxis")
            } description: {
                Text("progress.empty.description".localized)
            }
            .padding(.top, 30)
        } else if model.rows.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
                .padding(.top, 30)
        } else {
            // One flat lazy stack over pre-interleaved rows, for the same reason as the Trainings
            // list: every row draws a MiniSparkline `Canvas`, so the stack must be lazy — and a lazy
            // stack nested inside a lazy stack is an undocumented shape with reported stutter and a
            // reproducible hang, so the group headers are rows instead of containers.
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.rows) { row in
                    switch row {
                    case .header(let group, let count):
                        groupHeader(group: group, count: count)
                    case .exercise(let model):
                        NavigationLink(value: self.model.navigationValue(for: model)) {
                            FortschrittExerciseRowView(model: model)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { HapticManager.shared.light() })
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                }
            }
        }
    }

    private func groupHeader(group: String, count: Int) -> some View {
        HStack {
            Text(group.localized)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .kerning(-0.3)
                .foregroundStyle(Color.white)
            Spacer()
            Text("history.group.count".localized(count))
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.4))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

}
