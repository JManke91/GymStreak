//
//  ExerciseProgressChartView.swift
//  GymStreak
//
//  Redesigned per History Redesign (2026-04-22):
//  - Editorial header with muscle-group label + exercise name
//  - 3-stat hero (PR / Trend / Workouts)
//  - Chart card with metric tabs + headline + range pills
//  - "Letzte Sätze" list — one card per usage of the exercise per workout
//

import SwiftUI
import SwiftData
import Charts

struct ExerciseProgressChartView: View {
    let exerciseName: String
    let exerciseId: UUID?
    let availableExercises: [ExerciseWithHistory]
    /// The usage the Fortschritt row that pushed this screen summarised, or `nil` to take
    /// the screen's own default (the most recently trained usage).
    let initialUsage: ExerciseUsage.Key?
    @EnvironmentObject private var dependencies: AppDependencies

    init(
        exerciseName: String,
        exerciseId: UUID?,
        availableExercises: [ExerciseWithHistory],
        initialUsage: ExerciseUsage.Key? = nil
    ) {
        self.exerciseName = exerciseName
        self.exerciseId = exerciseId
        self.availableExercises = availableExercises
        self.initialUsage = initialUsage
    }

    init(exerciseName: String, exerciseId: UUID? = nil) {
        self.exerciseName = exerciseName
        self.exerciseId = exerciseId
        self.availableExercises = []
        self.initialUsage = nil
    }

    var body: some View {
        ExerciseProgressChartViewInternal(
            exerciseName: exerciseName,
            exerciseId: exerciseId,
            availableExercises: availableExercises,
            initialUsage: initialUsage,
            snapshotProvider: dependencies.historySnapshotProvider,
            proEntitlements: dependencies.proEntitlements,
            paywalls: dependencies.paywalls,
            deepDiveAllowanceGate: dependencies.makeAICoachAllowanceGate(for: .exerciseDeepDive)
        )
    }
}

private struct ExerciseProgressChartViewInternal: View {
    @State private var currentExerciseName: String
    @State private var currentExerciseId: UUID?
    @State private var showingMetricInfo = false
    let availableExercises: [ExerciseWithHistory]

    @StateObject private var viewModel: ExerciseProgressViewModel
    /// Kept only to pass through to the (out-of-scope) AI Coach deep-dive ViewModel API.
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // MARK: - AI Coach Deep-Dive

    @State private var deepDiveVM: ExerciseDeepDiveViewModel
    @State private var hasTappedAskCoach = false
    @Query private var allExercises: [Exercise]
    /// Retained so `switchToExercise` can rebuild the deep-dive ViewModel — a
    /// view may not construct the entitlement or the paywall seam itself, and
    /// the gate is a cheap, stateless composition of app-lifetime collaborators.
    private let deepDiveAllowanceGate: AICoachAllowanceGate

    init(
        exerciseName: String,
        exerciseId: UUID?,
        availableExercises: [ExerciseWithHistory],
        initialUsage: ExerciseUsage.Key?,
        snapshotProvider: HistorySnapshotProviding,
        proEntitlements: any ProEntitlementProviding,
        paywalls: any PaywallPresenting,
        deepDiveAllowanceGate: AICoachAllowanceGate
    ) {
        self._currentExerciseName = State(initialValue: exerciseName)
        self._currentExerciseId = State(initialValue: exerciseId)
        self.availableExercises = availableExercises
        self.deepDiveAllowanceGate = deepDiveAllowanceGate
        self._deepDiveVM = State(
            initialValue: ExerciseDeepDiveViewModel(allowanceGate: deepDiveAllowanceGate)
        )
        self._viewModel = StateObject(wrappedValue: ExerciseProgressViewModel(
            exerciseName: exerciseName,
            exerciseId: exerciseId,
            initialUsage: initialUsage,
            provider: snapshotProvider,
            proEntitlements: proEntitlements,
            paywalls: paywalls
        ))
    }

    private var primaryMuscleGroup: String {
        availableExercises.first(where: { $0.name == currentExerciseName })?.primaryMuscleGroup ?? ""
    }

    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    topBar
                    titleBlock
                    statTriple
                    chartCard
                    coachSection
                    recentUsagesSection
                    Color.clear.frame(height: 40)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .swipeBackEnabled()
        // Anchor for the floating coach bar's contextual suggestion chip.
        .onAppear {
            CoachScreenContext.shared.anchor = .exercise(name: currentExerciseName)
        }
        .onChange(of: currentExerciseName) { _, newName in
            CoachScreenContext.shared.anchor = .exercise(name: newName)
        }
        .onDisappear {
            deepDiveVM.cancel()
            CoachScreenContext.shared.anchor = nil
        }
        // One load for the whole screen. `.task(id:)` cancels the superseded fetch when
        // the exercise or the timeframe changes; the view model's generation counter
        // handles the rest, since the fetches inside the model actor are synchronous and
        // a cancelled one can still complete.
        .task(id: viewModel.loadKey) {
            await viewModel.load()
        }
        .task(id: currentExerciseId) {
            // Auto-load cached deep-dive on appear or when exercise switches
            if let exercise = resolvedExercise {
                await deepDiveVM.checkCache(exercise: exercise, locale: .current, modelContext: modelContext)
                // No cached narrative → the "Ask the Coach" button is showing.
                // Warm the model now so a tap streams tokens with minimal delay.
                if case .idle = deepDiveVM.state,
                   AICoachPreferences.shared.isExerciseDeepDiveEffectivelyEnabled,
                   AICoachAvailability.shared.isAvailable {
                    AICoachService.shared.prewarm()
                }
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                HapticManager.shared.light()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            // Only when this exercise was actually trained more than one way — see
            // `showsUsagePicker`. Next to the switcher because both answer "what am I
            // looking at", and both are reached at the same moment.
            if viewModel.showsUsagePicker {
                ExerciseUsageMenu(
                    options: viewModel.usageOptions,
                    selection: viewModel.selectedUsage,
                    selectedLabel: viewModel.selectedUsageLabel
                ) { viewModel.updateUsage($0) }
            }
            if !availableExercises.isEmpty {
                ExerciseSwitcherMenu(
                    currentExercise: currentExerciseName,
                    exercises: availableExercises
                ) { switchToExercise($0) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !primaryMuscleGroup.isEmpty {
                Text(primaryMuscleGroup.localized.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(DesignSystem.Colors.tint)
            }
            Text(currentExerciseName)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .kerning(-0.6)
                .foregroundStyle(Color.white)
                .lineLimit(2)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Stat triple

    private var statTriple: some View {
        HStack(spacing: 8) {
            hexStatCard(
                icon: "trophy.fill",
                color: Color(red: 1, green: 0.8, blue: 0),
                value: viewModel.personalRecordString ?? "-",
                label: "history.exercise.pr".localized
            )
            hexStatCard(
                icon: "arrow.up.right",
                // Neutral while the card prints something other than a percentage: with
                // several usages charted together there is no trend to call good or bad,
                // and a red "Gemischt" would read as a loss.
                color: viewModel.hasTrendValue
                    ? (viewModel.trendIsPositive ? DesignSystem.Colors.tint : Color(red: 1, green: 0.42, blue: 0.42))
                    : Color.white.opacity(0.4),
                value: viewModel.trendValueString,
                label: "history.exercise.trend".localized
            )
            hexStatCard(
                icon: "dumbbell.fill",
                color: Color(red: 90/255, green: 180/255, blue: 255/255),
                value: viewModel.sessionCountString ?? "-",
                label: "history.exercise.workouts".localized
            )
        }
        .padding(.horizontal, 16)
    }

    private func hexStatCard(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 26, height: 26)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color)
            }
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .kerning(-0.4)
                .monospacedDigit()
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Chart card

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            metricTabs
            // Only the readable half is locked (P2): the tabs and the range
            // pills stay live, because `.proLocked` disables what it blurs and
            // a user who cannot switch back off a Pro-only selection would be
            // stuck behind the blur.
            VStack(alignment: .leading, spacing: 14) {
                chartHeadline
                chartContent
            }
            .proLocked(viewModel.isChartLocked, placement: viewModel.chartLockPlacement) {
                viewModel.requestChartUnlock()
            }
            rangeSelector
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var metricTabs: some View {
        HStack(spacing: 16) {
            ForEach(viewModel.availableMetrics) { metric in
                Button {
                    HapticManager.shared.selection()
                    viewModel.updateMetric(metric)
                } label: {
                    HStack(spacing: 4) {
                        Text(metric == .maxWeight ? viewModel.selectedMetricTitle : metric.localizedTitle)
                            .font(.system(size: 13, weight: viewModel.selectedMetric == metric ? .bold : .medium, design: .rounded))
                            .foregroundStyle(viewModel.selectedMetric == metric ? Color.white : Color.white.opacity(0.45))
                        // Honest before the tap: the tab still works, it just
                        // leads to a blurred preview and the paywall.
                        if viewModel.isMetricLocked(metric) {
                            OnyxProBadge(style: .icon)
                        }
                    }
                    .padding(.bottom, 4)
                    .overlay(
                        Rectangle()
                            .fill(viewModel.selectedMetric == metric ? DesignSystem.Colors.tint : Color.clear)
                            .frame(height: 2)
                            .padding(.top, 2),
                        alignment: .bottom
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button {
                showingMetricInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingMetricInfo) {
                MetricInfoPopover(metric: viewModel.selectedMetric)
            }
        }
        .padding(.horizontal, 6)
    }

    private var chartHeadline: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(viewModel.selectedMetricTitle.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.white.opacity(0.4))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(latestHeadline)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .kerning(-0.8)
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                Text(viewModel.selectedMetric.unit)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.5))
                if let trend = viewModel.trendPercentageString {
                    Text(trend)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(viewModel.trendIsPositive ? DesignSystem.Colors.tint : Color(red: 1, green: 0.42, blue: 0.42))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            (viewModel.trendIsPositive ? DesignSystem.Colors.tint : Color(red: 1, green: 0.42, blue: 0.42))
                                .opacity(0.12)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
        }
        .padding(.horizontal, 6)
    }

    private var latestHeadline: String {
        guard let last = viewModel.progressData?.dataPoints.last else { return "-" }
        let value = last.value(for: viewModel.selectedMetric)
        if viewModel.selectedMetric == .volume {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }

    @ViewBuilder
    private var chartContent: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .frame(height: 180)
        } else if let data = viewModel.progressData, data.hasEnoughData {
            ProgressChartContent(
                data: data,
                metric: viewModel.selectedMetric,
                // The window the data actually covers — a Pro-only selection
                // blurs the last unlocked window rather than fetching a wider one.
                timeframe: viewModel.chartTimeframe,
                selectedDataPoint: viewModel.selectedDataPoint,
                onSelectPoint: { viewModel.selectDataPoint($0, for: viewModel.selectedMetric) },
                onClearSelection: { viewModel.clearSelection() }
            )
            .frame(height: 180)
            .padding(.horizontal, 2)
        } else {
            emptyChart
                .frame(height: 180)
        }
    }

    /// Two emptinesses, two lines of copy — both resolved by the view model, which
    /// reads one already-loaded `isEmpty` to tell "never trained" apart from "not
    /// inside the selected window". The windowed line names the date that usage was
    /// last trained (formatted during `load()`), so the range pills sitting directly
    /// below can be tapped once, correctly.
    private var emptyChart: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 32))
                .foregroundStyle(Color.white.opacity(0.25))
            Text(viewModel.emptyChartReason.titleKey.localized)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
            Text(viewModel.emptyChartMessage)
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
    }

    private var rangeSelector: some View {
        HStack(spacing: 4) {
            ForEach(ChartTimeframe.allCases) { timeframe in
                Button {
                    HapticManager.shared.selection()
                    viewModel.updateTimeframe(timeframe)
                } label: {
                    HStack(spacing: 3) {
                        Text(timeframe.localizedTitle)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                viewModel.selectedTimeframe == timeframe
                                    ? DesignSystem.Colors.textOnTint
                                    : Color.white.opacity(0.6)
                            )
                        if viewModel.isTimeframeLocked(timeframe) {
                            OnyxProBadge(style: .icon)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        viewModel.selectedTimeframe == timeframe
                            ? DesignSystem.Colors.tint
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 6)
    }

    // MARK: - Recent sets

    private var recentUsagesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("history.exercise.recent".localized)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                Spacer()
                Text("history.exercise.entries".localized(viewModel.recentUsages.count))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            .padding(.horizontal, 20)

            if viewModel.recentUsages.isEmpty {
                Text("chart.empty.message".localized)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                // Plain stack on purpose: the view model caps this list at
                // `recentSessionLimit` (8) **sessions**, and a session contributes one
                // card per usage of the exercise — a handful at most. Bounded by the
                // routine's shape, not by history length, so it is not user-scaled data.
                VStack(spacing: 8) {
                    ForEach(viewModel.recentUsages) { usage in
                        RecentUsageCardView(entry: usage)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - AI Coach Coach Section

    @ViewBuilder
    private var coachSection: some View {
        let prefs = AICoachPreferences.shared
        let avail = AICoachAvailability.shared
        if prefs.isExerciseDeepDiveEffectivelyEnabled, avail.isAvailable, let exercise = resolvedExercise {
            Group {
                if case .idle = deepDiveVM.state, !hasTappedAskCoach {
                    VStack(spacing: 10) {
                        // §8 placement D — the free-tier allowance hint, above
                        // the button that spends it. Blocks nothing.
                        if let nudge = deepDiveVM.allowanceNudge {
                            OnyxCapNudge(text: nudge.text, used: nudge.used, limit: nudge.limit)
                        }
                        CoachDeepDiveButton(exerciseName: currentExerciseName) {
                            // Only commit to the surface if the generation was
                            // admitted: a refused tap raises the paywall and
                            // leaves the button where it was.
                            if deepDiveVM.generate(
                                exercise: exercise,
                                locale: .current,
                                modelContext: modelContext
                            ) {
                                hasTappedAskCoach = true
                            }
                        }
                    }
                    .transition(.opacity)
                } else {
                    CoachDeepDiveSurface(
                        state: deepDiveVM.state,
                        exerciseName: currentExerciseName,
                        onRegenerate: {
                            deepDiveVM.regenerate(
                                exercise: exercise,
                                locale: .current,
                                modelContext: modelContext
                            )
                        }
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: deepDiveVM.state)
            .padding(.horizontal, 16)
        }
    }

    /// Resolves the live `Exercise` from SwiftData using `currentExerciseId` (preferred)
    /// or by name match when the chart was opened without an explicit id.
    private var resolvedExercise: Exercise? {
        if let id = currentExerciseId {
            return allExercises.first(where: { $0.id == id })
        }
        return allExercises.first(where: { $0.name == currentExerciseName })
    }

    // MARK: - Data

    private func switchToExercise(_ exercise: ExerciseWithHistory) {
        currentExerciseName = exercise.name
        currentExerciseId = exercise.exerciseId
        // Changes `viewModel.loadKey`, which restarts the `.task(id:)` load. The switched-to
        // exercise carries its own Fortschritt headline usage, so switching lands where
        // tapping that exercise's row would have.
        viewModel.updateExercise(
            exercise.name,
            exerciseId: exercise.exerciseId,
            initialUsage: exercise.initialUsage
        )
        // Reset deep-dive state when the user switches exercises
        deepDiveVM = ExerciseDeepDiveViewModel(allowanceGate: deepDiveAllowanceGate)
        hasTappedAskCoach = false
    }
}

// MARK: - Exercise Switcher Menu

struct ExerciseSwitcherMenu: View {
    let currentExercise: String
    let exercises: [ExerciseWithHistory]
    let onSelect: (ExerciseWithHistory) -> Void

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
                            onSelect(exercise)
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
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                Text("switch".localized)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityLabel("chart.switch_exercise".localized(currentExercise))
    }
}

// MARK: - Progress Chart Content (kept from original for Swift Charts rendering)

struct ProgressChartContent: View {
    let data: ExerciseProgressData
    let metric: ProgressMetric
    let timeframe: ChartTimeframe
    let selectedDataPoint: SelectedDataPoint?
    let onSelectPoint: (ExerciseProgressDataPoint) -> Void
    let onClearSelection: () -> Void

    private var yDomain: ClosedRange<Double> {
        let values = data.dataPoints.map { $0.value(for: metric) }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let padding = max((maxValue - minValue) * 0.1, maxValue * 0.05)
        let lower = max(0, minValue - padding)
        let upper = maxValue + padding
        guard lower < upper else {
            let fallback = max(maxValue * 0.1, 1)
            return max(0, maxValue - fallback)...(maxValue + fallback)
        }
        return lower...upper
    }

    var body: some View {
        Chart {
            ForEach(data.dataPoints) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Min", yDomain.lowerBound),
                    yEnd: .value(metric.localizedTitle, point.value(for: metric))
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [DesignSystem.Colors.tint.opacity(0.28), DesignSystem.Colors.tint.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Date", point.date),
                    y: .value(metric.localizedTitle, point.value(for: metric))
                )
                .foregroundStyle(DesignSystem.Colors.tint)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value("Date", point.date),
                    y: .value(metric.localizedTitle, point.value(for: metric))
                )
                .foregroundStyle(DesignSystem.Colors.tint)
                .symbolSize(20)
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
                AxisValueLabel(format: axisDateFormat)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                    .foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel {
                    if let doubleValue = value.as(Double.self) {
                        Text(formatCompactValue(doubleValue, unit: nil))
                            .foregroundStyle(Color.white.opacity(0.45))
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
        case .week:         return .dateTime.weekday(.abbreviated)
        case .month:        return .dateTime.month(.abbreviated).day()
        case .threeMonths,
             .year:         return .dateTime.month(.abbreviated)
        case .all:          return .dateTime.month(.abbreviated).year(.twoDigits)
        }
    }

    private func handleChartTap(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        let origin: CGPoint
        if let frame = proxy.plotFrame {
            origin = geo[frame].origin
        } else {
            origin = .zero
        }
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
