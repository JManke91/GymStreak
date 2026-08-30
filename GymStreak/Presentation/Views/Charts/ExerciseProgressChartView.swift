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
            legacyAttribution: dependencies.legacyHistoryAttribution,
            proEntitlements: dependencies.proEntitlements,
            paywalls: dependencies.paywalls,
            weightUnitPreference: dependencies.weightUnitPreference,
            deepDiveAllowanceGate: dependencies.makeAICoachAllowanceGate(for: .exerciseDeepDive),
            deepDiveFacts: dependencies.exerciseDeepDiveFacts
        )
    }
}

/// What the deep-dive narrative describes: one exercise, one usage. Both have to be part
/// of the `.task(id:)` key, because the cached narrative is keyed by both.
///
/// `usage` is `ExerciseProgressViewModel.resolvedUsage`, so it is `nil` until a load has
/// answered which usage the screen is showing. Keying on `selectedUsage` instead would
/// run the cache probe — a history fetch on the shared History model actor, queued ahead
/// of this screen's own chart load — once against the `.combined` placeholder and again
/// against the answer, on every screen open.
private struct DeepDiveContext: Equatable {
    let exerciseId: UUID?
    let usage: ExerciseUsageSelection?
}

private struct ExerciseProgressChartViewInternal: View {
    @State private var currentExerciseName: String
    @State private var currentExerciseId: UUID?
    @State private var showingMetricInfo = false
    let availableExercises: [ExerciseWithHistory]

    @StateObject private var viewModel: ExerciseProgressViewModel
    /// Read only to notice a change: the plotted series is converted in the
    /// ViewModel, which holds the same preference this environment value is
    /// published from.
    @Environment(\.weightUnit) private var weightUnit
    @Environment(\.dismiss) private var dismiss

    // MARK: - AI Coach Deep-Dive

    @State private var deepDiveVM: ExerciseDeepDiveViewModel
    @State private var hasTappedAskCoach = false
    @Query private var allExercises: [Exercise]
    /// Retained so `switchToExercise` can rebuild the deep-dive ViewModel — a
    /// view may not construct the entitlement or the paywall seam itself, and
    /// the gate is a cheap, stateless composition of app-lifetime collaborators.
    private let deepDiveAllowanceGate: AICoachAllowanceGate
    /// Retained for the same reason: the deep-dive's model-actor-backed history
    /// boundary, which only the composition root may hand out.
    private let deepDiveFacts: any ExerciseDeepDiveFactProviding

    init(
        exerciseName: String,
        exerciseId: UUID?,
        availableExercises: [ExerciseWithHistory],
        initialUsage: ExerciseUsage.Key?,
        snapshotProvider: HistorySnapshotProviding,
        legacyAttribution: any LegacyHistoryAttributing,
        proEntitlements: any ProEntitlementProviding,
        paywalls: any PaywallPresenting,
        weightUnitPreference: any WeightUnitPreferenceProviding,
        deepDiveAllowanceGate: AICoachAllowanceGate,
        deepDiveFacts: any ExerciseDeepDiveFactProviding
    ) {
        self._currentExerciseName = State(initialValue: exerciseName)
        self._currentExerciseId = State(initialValue: exerciseId)
        self.availableExercises = availableExercises
        self.deepDiveAllowanceGate = deepDiveAllowanceGate
        self.deepDiveFacts = deepDiveFacts
        self._deepDiveVM = State(
            initialValue: ExerciseDeepDiveViewModel(
                allowanceGate: deepDiveAllowanceGate,
                facts: deepDiveFacts
            )
        )
        self._viewModel = StateObject(wrappedValue: ExerciseProgressViewModel(
            exerciseName: exerciseName,
            exerciseId: exerciseId,
            initialUsage: initialUsage,
            provider: snapshotProvider,
            legacyAttribution: legacyAttribution,
            proEntitlements: proEntitlements,
            paywalls: paywalls,
            weightUnitPreference: weightUnitPreference
        ))
    }

    /// The list entry for the exercise on screen, matched by id first: two library
    /// exercises may share a display name, and a name match would then describe the other
    /// one. `nil` when the screen was pushed without a list behind it.
    private var currentEntry: ExerciseWithHistory? {
        currentExerciseId.flatMap { id in
            availableExercises.first { $0.exerciseId == id }
        } ?? availableExercises.first { $0.name == currentExerciseName }
    }

    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    topBar
                    titleBlock
                    legacyAttributionBanner
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
        // The unit is not part of `loadKey`, so a trip to Settings and back would
        // otherwise leave the plotted series in the old unit under a relabelled
        // axis. Nothing is refetched — only the conversion is redone.
        .onChange(of: weightUnit) { _, _ in
            viewModel.refreshChartSeries()
        }
        .onDisappear {
            deepDiveVM.cancel()
            CoachScreenContext.shared.anchor = nil
        }
        // A narrative describes one usage, so the one on screen is retired the moment the
        // user picks another. `requestedUsage`, not `selectedUsage`: the request changes
        // on the tap, while the selection only catches up when the reload lands — and the
        // stale sentences must not outlive the tap that invalidated them.
        .onChange(of: viewModel.requestedUsage) { _, _ in
            resetDeepDive()
        }
        // One load for the whole screen. `.task(id:)` cancels the superseded fetch when
        // the exercise or the timeframe changes; the view model's generation counter
        // handles the rest, since the fetches inside the model actor are synchronous and
        // a cancelled one can still complete.
        .task(id: viewModel.loadKey) {
            await viewModel.load()
        }
        // Keyed on the usage as well as the exercise: the cached narrative belongs to the
        // (exercise, usage) pair, so switching usage has its own cache to check. It waits
        // for `resolvedUsage` so the probe runs once, against the usage actually charted.
        .task(id: DeepDiveContext(exerciseId: currentExerciseId, usage: viewModel.resolvedUsage)) {
            // Auto-load cached deep-dive once the load has said which usage is charted,
            // and again when the exercise or that usage changes.
            if let usage = deepDiveUsage, let exercise = resolvedExercise {
                await deepDiveVM.checkCache(exerciseId: exercise.id, usage: usage)
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
                    currentExerciseId: currentExerciseId,
                    exercises: availableExercises
                ) { switchToExercise($0) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Title

    /// Resolved once per title build, not once per line: `currentEntry` scans the list.
    ///
    /// The eyebrow carries the equipment as well as the muscle group where another live
    /// exercise shares this name. With the switcher closed the title is the only thing
    /// naming the exercise, and a bare "Biceps Curls" cannot say which of the two it is —
    /// the same rule the Fortschritt row and the switcher apply.
    private var titleBlock: some View {
        let entry = currentEntry
        let muscleGroup = entry?.primaryMuscleGroup ?? ""
        let eyebrow: String = {
            guard let equipment = entry?.equipmentQualifier else { return muscleGroup.localized }
            return "progress.exercise.with_equipment".localized(
                muscleGroup.localized,
                equipment.displayName
            )
        }()
        return VStack(alignment: .leading, spacing: 2) {
            if !muscleGroup.isEmpty {
                Text(eyebrow.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(DesignSystem.Colors.tint)
                    .lineLimit(1)
            }
            Text(currentExerciseName)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .kerning(-0.6)
                .foregroundStyle(Color.white)
                .lineLimit(2)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Unattributable legacy history

    /// Above the numbers it is about. Everything below this line — the record, the trend,
    /// the workout count, the chart and the recent sets — is computed *without* the
    /// workouts it names, so the user has to read it before, not after.
    ///
    /// The whole block is absent whenever nothing is being withheld, which is the case for
    /// every uniquely-named exercise.
    @ViewBuilder
    private var legacyAttributionBanner: some View {
        if viewModel.canAttributeLegacyHistory,
           let finding = viewModel.unattributedLegacy,
           let message = viewModel.unattributedLegacyMessage {
            LegacyHistoryAttributionBanner(
                message: message,
                exerciseName: currentExerciseName,
                sessionCount: finding.sessionCount,
                isAttributing: viewModel.isAttributingLegacyHistory
            ) {
                Task { await viewModel.attributeLegacyHistory() }
            }
        }
    }

    // MARK: - Stat triple

    /// Every card here describes the **selected range**, not all of history — see
    /// `ExerciseProgressViewModel.statLabel(_:)` for why each label says so.
    private var statTriple: some View {
        HStack(spacing: 8) {
            hexStatCard(
                icon: "trophy.fill",
                color: Color(red: 1, green: 0.8, blue: 0),
                value: viewModel.personalRecordString ?? "-",
                label: viewModel.statLabel("history.exercise.pr")
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
                label: viewModel.statLabel("history.exercise.trend")
            )
            hexStatCard(
                icon: "dumbbell.fill",
                color: Color(red: 90/255, green: 180/255, blue: 255/255),
                value: viewModel.sessionCountString ?? "-",
                label: viewModel.statLabel("history.exercise.workouts")
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
            // The label now carries the range ("REKORD · 3M"), so it must stay on one
            // line: a card that wrapped would grow taller than the two beside it.
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Color.white.opacity(0.45))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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
                        Text(viewModel.title(for: metric))
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
                Text(viewModel.headlineValue)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .kerning(-0.8)
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                Text(viewModel.headlineUnitWord)
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

    @ViewBuilder
    private var chartContent: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .frame(height: 180)
        } else if let data = viewModel.progressData, data.hasEnoughData,
                  let series = viewModel.chartSeries {
            ProgressChartContent(
                series: series,
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
        if prefs.isExerciseDeepDiveEffectivelyEnabled, avail.isAvailable,
           let exercise = resolvedExercise,
           // Nothing to describe until the load has said which usage is charted.
           let usage = deepDiveUsage {
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
                                exerciseId: exercise.id,
                                exerciseName: exercise.name,
                                usage: usage,
                                locale: .current,
                                weightUnit: weightUnit
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
                        // Only where a variant menu actually exists: on a single-usage
                        // exercise `selectedUsageLabel` is "Alle Varianten", which would
                        // name a choice this screen never offers.
                        usageLabel: viewModel.showsUsagePicker ? viewModel.selectedUsageLabel : nil,
                        onRegenerate: {
                            deepDiveVM.regenerate(
                                exerciseId: exercise.id,
                                exerciseName: exercise.name,
                                usage: usage,
                                locale: .current,
                                weightUnit: weightUnit
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
        resetDeepDive()
    }

    /// The usage the coach should describe, paired with the label the picker is showing
    /// for it — so the narrative names the variant exactly as the menu the user picked it
    /// in does. Two reads of already-loaded view-model state, so `body` may read it.
    ///
    /// Built from `resolvedUsage`, never from `selectedUsage`: between a usage tap and the
    /// reload landing, `selectedUsage` still names the *previous* variant, and generating
    /// then would spend a monthly allowance unit on a narrative for the usage the user
    /// just left. `nil` in that window, and `coachSection` renders nothing.
    private var deepDiveUsage: DeepDiveUsage? {
        viewModel.resolvedUsage.map {
            DeepDiveUsage(selection: $0, label: viewModel.selectedUsageLabel)
        }
    }

    /// Retires the narrative on screen. Called whenever the body of work it describes
    /// changes underneath it — a different exercise, or a different usage of this one.
    private func resetDeepDive() {
        deepDiveVM.cancel()
        deepDiveVM = ExerciseDeepDiveViewModel(
            allowanceGate: deepDiveAllowanceGate,
            facts: deepDiveFacts
        )
        hasTappedAskCoach = false
    }
}

// MARK: - Progress Chart Content (kept from original for Swift Charts rendering)

struct ProgressChartContent: View {
    /// Already in the user's unit, with its y-domain derived from the same
    /// converted numbers — see `ChartSeries` for why neither is computed here.
    let series: ChartSeries
    /// Only the metric's *name*, which labels the marks. The plotted numbers come
    /// from `series`.
    let metric: ProgressMetric
    let timeframe: ChartTimeframe
    let selectedDataPoint: SelectedDataPoint?
    let onSelectPoint: (ExerciseProgressDataPoint) -> Void
    let onClearSelection: () -> Void

    var body: some View {
        Chart {
            ForEach(series.points) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Min", series.yDomain.lowerBound),
                    yEnd: .value(metric.localizedTitle, point.value)
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
                    y: .value(metric.localizedTitle, point.value)
                )
                .foregroundStyle(DesignSystem.Colors.tint)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value("Date", point.date),
                    y: .value(metric.localizedTitle, point.value)
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
        .chartYScale(domain: series.yDomain)
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
                        Text(series.axisLabel(for: doubleValue))
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
        let nearest = series.points.min(by: {
            abs($0.date.timeIntervalSince(tappedDate)) < abs($1.date.timeIntervalSince(tappedDate))
        })
        if let nearest {
            // The canonical point, not the converted one: the annotation's figure
            // is formatted from kilograms like every other weight in the app.
            onSelectPoint(nearest.source)
        } else {
            onClearSelection()
        }
    }
}
