//
//  ExerciseProgressChartView.swift
//  GymStreak
//

import SwiftUI
import Charts

struct ExerciseProgressChartView: View {
    @State private var currentExerciseName: String
    @State private var showingMetricInfo = false
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
                ChartTimeframePicker(selection: $viewModel.selectedTimeframe) { timeframe in
                    viewModel.updateTimeframe(timeframe)
                }
                .padding(.horizontal)

                // Metric Picker with Info Button
                HStack {
                    Picker("chart.metric".localized, selection: $viewModel.selectedMetric) {
                        ForEach(ProgressMetric.allCases) { metric in
                            Text(metric.localizedTitle).tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: viewModel.selectedMetric) { _, newValue in
                        viewModel.updateMetric(newValue)
                    }

                    Button {
                        showingMetricInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.body)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                    .accessibilityLabel("chart.metric.info".localized)
                    .popover(isPresented: $showingMetricInfo) {
                        MetricInfoPopover(metric: viewModel.selectedMetric)
                    }
                }
                .padding(.horizontal)

                // Chart Content
                if viewModel.isLoading {
                    ProgressView()
                        .frame(height: 250)
                } else if let data = viewModel.progressData, data.hasEnoughData {
                    ProgressChartContent(
                        data: data,
                        metric: viewModel.selectedMetric,
                        timeframe: viewModel.selectedTimeframe,
                        selectedDataPoint: viewModel.selectedDataPoint,
                        onSelectPoint: { viewModel.selectDataPoint($0, for: viewModel.selectedMetric) },
                        onClearSelection: { viewModel.clearSelection() }
                    )
                    .frame(height: 250)
                    .padding(.horizontal)

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
    let timeframe: ChartTimeframe
    let selectedDataPoint: SelectedDataPoint?
    let onSelectPoint: (ExerciseProgressDataPoint) -> Void
    let onClearSelection: () -> Void

    /// Stable Y-axis domain to prevent axis recalculation on selection changes
    private var yDomain: ClosedRange<Double> {
        let values = data.dataPoints.map { $0.value(for: metric) }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0

        // Add 10% padding; ensure minimum is 0 for weight-based metrics
        let padding = max((maxValue - minValue) * 0.1, maxValue * 0.05)
        let lower = max(0, minValue - padding)
        let upper = maxValue + padding

        // Avoid zero-range domain (all values identical or single point)
        guard lower < upper else {
            let fallback = max(maxValue * 0.1, 1)
            return max(0, maxValue - fallback)...(maxValue + fallback)
        }

        return lower...upper
    }

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

            if let selected = selectedDataPoint {
                RuleMark(x: .value("Selected", selected.dataPoint.date))
                    .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, spacing: 8) {
                        ChartDataPointAnnotation(selectedPoint: selected)
                    }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: timeframe.axisStrideComponent, count: timeframe.axisStrideValue)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(DesignSystem.Colors.divider)
                AxisValueLabel(format: axisDateFormat)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(DesignSystem.Colors.divider)
                AxisValueLabel {
                    if let doubleValue = value.as(Double.self) {
                        Text(formatCompactValue(doubleValue, unit: metric.unit))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        handleChartTap(at: location, proxy: proxy, geo: geo)
                    }
            }
        }
    }

    private var axisDateFormat: Date.FormatStyle {
        switch timeframe {
        case .week:
            return .dateTime.weekday(.abbreviated)
        case .month:
            return .dateTime.month(.abbreviated).day()
        case .threeMonths, .year:
            return .dateTime.month(.abbreviated)
        case .all:
            return .dateTime.month(.abbreviated).year(.twoDigits)
        }
    }

    private func handleChartTap(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        let origin = geo[proxy.plotAreaFrame].origin
        let adjustedX = location.x - origin.x

        guard let tappedDate: Date = proxy.value(atX: adjustedX) else {
            onClearSelection()
            return
        }

        let nearest = data.dataPoints.min(by: {
            abs($0.date.timeIntervalSince(tappedDate)) < abs($1.date.timeIntervalSince(tappedDate))
        })

        if let nearest {
            onSelectPoint(nearest)
        } else {
            onClearSelection()
        }
    }
}

#Preview {
    NavigationStack {
        ExerciseProgressChartView(exerciseName: "Bench Press")
    }
    .preferredColorScheme(.dark)
}
