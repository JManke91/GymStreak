//
//  ExerciseProgressChartView.swift
//  GymStreak
//

import SwiftUI
import Charts

struct ExerciseProgressChartView: View {
    @State private var currentExerciseName: String
    let availableExercises: [ExerciseWithHistory]

    @StateObject private var viewModel: ExerciseProgressViewModel
    @Environment(\.modelContext) private var modelContext

    // Initializer for direct navigation (from Progress list)
    init(exerciseName: String, availableExercises: [ExerciseWithHistory]) {
        self._currentExerciseName = State(initialValue: exerciseName)
        self.availableExercises = availableExercises
        self._viewModel = StateObject(wrappedValue: ExerciseProgressViewModel(exerciseName: exerciseName))
    }

    // Convenience initializer for navigation from workout detail (no switching)
    init(exerciseName: String) {
        self._currentExerciseName = State(initialValue: exerciseName)
        self.availableExercises = []
        self._viewModel = StateObject(wrappedValue: ExerciseProgressViewModel(exerciseName: exerciseName))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Timeframe Picker
                ChartTimeframePicker(selection: $viewModel.selectedTimeframe) { timeframe in
                    viewModel.updateTimeframe(timeframe)
                }
                .padding(.horizontal)

                // Metric Picker
                Picker("chart.metric".localized, selection: $viewModel.selectedMetric) {
                    ForEach(ProgressMetric.allCases) { metric in
                        Text(metric.localizedTitle).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: viewModel.selectedMetric) { _, newValue in
                    viewModel.updateMetric(newValue)
                }

                // Chart Content
                if viewModel.isLoading {
                    ProgressView()
                        .frame(height: 250)
                } else if let data = viewModel.progressData, data.hasEnoughData {
                    ProgressChartContent(
                        data: data,
                        metric: viewModel.selectedMetric
                    )
                    .frame(height: 250)
                    .padding(.horizontal)

                    // Summary Stats
                    SummaryStatsView(viewModel: viewModel)
                        .padding(.horizontal)
                } else {
                    EmptyChartView()
                        .frame(height: 250)
                }
            }
            .padding(.vertical)
        }
        .background(DesignSystem.Colors.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !availableExercises.isEmpty {
                ToolbarItem(placement: .principal) {
                    ExerciseSwitcherMenu(
                        currentExercise: currentExerciseName,
                        exercises: availableExercises
                    ) { newExercise in
                        switchToExercise(newExercise)
                    }
                }
            } else {
                ToolbarItem(placement: .principal) {
                    Text(currentExerciseName)
                        .font(.headline)
                }
            }
        }
        .onAppear {
            viewModel.updateModelContext(modelContext)
        }
    }

    private func switchToExercise(_ exerciseName: String) {
        currentExerciseName = exerciseName
        viewModel.updateExercise(exerciseName, context: modelContext)
    }
}

// MARK: - Exercise Switcher Menu

struct ExerciseSwitcherMenu: View {
    let currentExercise: String
    let exercises: [ExerciseWithHistory]
    let onSelect: (String) -> Void

    // Group exercises by muscle group for the menu
    private var groupedExercises: [String: [ExerciseWithHistory]] {
        Dictionary(grouping: exercises) { $0.primaryMuscleGroup }
    }

    private var sortedMuscleGroups: [String] {
        groupedExercises.keys.sorted()
    }

    var body: some View {
        Menu {
            ForEach(sortedMuscleGroups, id: \.self) { muscleGroup in
                Section(muscleGroup.localized) {
                    ForEach(groupedExercises[muscleGroup] ?? [], id: \.name) { exercise in
                        Button {
                            onSelect(exercise.name)
                        } label: {
                            HStack {
                                Text(exercise.name)
                                if exercise.name == currentExercise {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentExercise)
                    .font(.headline)
                    .lineLimit(1)
                Image(systemName: "chevron.down.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("chart.switch_exercise".localized(currentExercise))
    }
}

// MARK: - Progress Chart Content

struct ProgressChartContent: View {
    let data: ExerciseProgressData
    let metric: ProgressMetric

    var body: some View {
        Chart {
            ForEach(data.dataPoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value(metric.localizedTitle, point.value(for: metric))
                )
                .foregroundStyle(DesignSystem.Colors.tint)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Date", point.date),
                    y: .value(metric.localizedTitle, point.value(for: metric))
                )
                .foregroundStyle(DesignSystem.Colors.tint)
                .symbolSize(30)
            }

            // Area under the line
            ForEach(data.dataPoints) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value(metric.localizedTitle, point.value(for: metric))
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            DesignSystem.Colors.tint.opacity(0.3),
                            DesignSystem.Colors.tint.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(DesignSystem.Colors.divider)
                AxisValueLabel()
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(DesignSystem.Colors.divider)
                AxisValueLabel {
                    if let doubleValue = value.as(Double.self) {
                        Text(String(format: "%.0f", doubleValue))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }
            }
        }
    }
}

// MARK: - Summary Stats View

struct SummaryStatsView: View {
    @ObservedObject var viewModel: ExerciseProgressViewModel

    var body: some View {
        HStack(spacing: 16) {
            // Personal Record
            StatCard(
                title: "chart.personal_record".localized,
                value: viewModel.personalRecordString ?? "-",
                icon: "trophy.fill",
                iconColor: .yellow
            )

            // Trend
            StatCard(
                title: "chart.trend".localized,
                value: viewModel.trendPercentageString ?? "-",
                icon: viewModel.trendIsPositive ? "arrow.up.right" : "arrow.down.right",
                iconColor: viewModel.trendIsPositive ? DesignSystem.Colors.success : DesignSystem.Colors.warning
            )

            // Sessions
            StatCard(
                title: "chart.sessions".localized,
                value: viewModel.sessionCountString ?? "-",
                icon: "figure.strengthtraining.traditional",
                iconColor: DesignSystem.Colors.tint
            )
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let iconColor: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)

            Text(value)
                .font(.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text(title)
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Empty Chart View

struct EmptyChartView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            VStack(spacing: 4) {
                Text("chart.empty.title".localized)
                    .font(.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("chart.empty.message".localized)
                    .font(.subheadline)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    NavigationStack {
        ExerciseProgressChartView(exerciseName: "Bench Press")
    }
    .preferredColorScheme(.dark)
}
