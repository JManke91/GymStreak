//
//  FullScreenSetEditorView.swift
//  GymStreakWatch Watch App
//
//  Created by Claude Code
//

import SwiftUI
import WatchKit

/// Full-screen set editor optimized for Apple Watch
/// Eliminates scrolling conflicts by showing only the current set
/// Digital Crown adjusts focused value without interfering with list scrolling
struct FullScreenSetEditorView: View {
    /// The initial exercise passed in (used as fallback; display follows
    /// viewModel.currentExercise / currentSetIndex)
    let exercise: ActiveWorkoutExercise
    @EnvironmentObject var viewModel: WatchWorkoutViewModel

    @State private var focusedField: FocusedField = .weight
    @State private var showDoneFlash = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let metrics = WorkoutScreenMetrics.current

    enum FocusedField {
        case weight, reps
    }

    /// Stable identities for the two items in the steppers/metrics row. Keying
    /// the ForEach on these (never on position) is what lets SwiftUI animate the
    /// focus swap as a slide instead of a crossfade.
    private enum ClusterSlot: Hashable {
        case steppers, metrics
    }

    private var hasMetrics: Bool {
        viewModel.heartRate != nil && viewModel.activeCalories != nil
    }

    /// Row order: the steppers sit on the focused card's side (weight = left,
    /// reps = right); the metrics take the opposite side, dropped entirely until
    /// HealthKit delivers values.
    private var clusterOrder: [ClusterSlot] {
        let base: [ClusterSlot] = focusedField == .weight
            ? [.steppers, .metrics]
            : [.metrics, .steppers]
        return hasMetrics ? base : base.filter { $0 != .metrics }
    }

    /// Outer edge each slot hugs — derived from focus (not row position) so the
    /// steppers stay on the correct side even when the metrics slot is absent.
    private func alignment(for slot: ClusterSlot) -> Alignment {
        switch slot {
        case .steppers: return focusedField == .weight ? .leading : .trailing
        case .metrics: return focusedField == .weight ? .trailing : .leading
        }
    }

    @ViewBuilder
    private func clusterView(for slot: ClusterSlot) -> some View {
        switch slot {
        case .steppers: steppersCluster
        case .metrics: metricsCluster
        }
    }

    /// The current exercise from the ViewModel - used for superset navigation
    /// Falls back to the passed-in exercise if ViewModel doesn't have one
    private var displayedExercise: ActiveWorkoutExercise {
        viewModel.currentExercise ?? exercise
    }

    /// Total sets for the current exercise being displayed
    private var totalSets: Int {
        displayedExercise.sets.count
    }

    /// The set index within the displayed exercise (from ViewModel)
    private var displayedSetIndex: Int {
        viewModel.currentSetIndex
    }

    private var currentSet: Binding<ActiveWorkoutSet> {
        Binding(
            get: {
                let setIndex = min(displayedSetIndex, displayedExercise.sets.count - 1)
                return displayedExercise.sets[max(0, setIndex)]
            },
            set: { updatedSet in
                viewModel.updateSet(updatedSet, in: displayedExercise.id)
            }
        )
    }

    /// Shifts the action row down past the bottom safe-area boundary so the
    /// capsule's visual bottom sits `footerBottomGap` above the physical screen
    /// edge, matching the design. Accounts for the 44 pt touch frame centering
    /// the smaller capsule. Never pulls the row upward (clamped at 0).
    private func bottomSafeAreaOverlap(for inset: CGFloat) -> CGFloat {
        let touchFramePadding = (OnyxWatch.Dimensions.minTouchTarget - metrics.completeButtonHeight) / 2
        return max(0, inset + touchFramePadding - metrics.footerBottomGap)
    }

    var body: some View {
        // No NavigationStack of its own: this view is pushed onto the shared
        // stack owned by ActiveWorkoutView. A second stack created mid-swap
        // fed "ToolbarReader/navigationEventHandlers tried to update multiple
        // times per frame" warnings.
        GeometryReader { geometry in
            ZStack {
                // Background extends edge-to-edge
                OnyxWatch.Colors.background
                    .ignoresSafeArea()

                // The action row is pinned to the bottom; the editing group
                // (steppers/metrics/cards) floats centered in the remaining
                // space via the two flexible spacers, so large cases don't
                // pile all the leftover space above the steppers. On small
                // cases the spacers collapse to the compact design spacing.
                VStack(spacing: 0) {
                    // Top zone: exercise name + workout-completion percent +
                    // per-exercise segment bar (design §4).
                    WorkoutTopProgressView(
                        exerciseName: displayedExercise.name,
                        exerciseIndex: viewModel.currentExerciseIndex,
                        exerciseCount: viewModel.exercises.count,
                        setIndex: displayedSetIndex,
                        setCount: totalSets,
                        exerciseProgress: viewModel.progressSegments
                    )
                    .padding(.horizontal, 2)

                    Spacer(minLength: 4)

                    // Steppers (adjust the focused value) + live metrics.
                    // The +/- cluster stays on the same side as the focused value
                    // card (weight = left, reps = right) so it reads as directly
                    // controlling that card; the HR/kCal metrics take the other
                    // side and the two SLIDE past each other when focus changes.
                    // A ForEach keyed by the stable ClusterSlot identity (not by
                    // position) lets SwiftUI treat the reorder as a move and
                    // interpolate each cluster's frame — an if/else swap only
                    // crossfades, because the branches are distinct identities.
                    // Equal-width, outer-aligned frames stand in for the Spacer
                    // (a Spacer between reordered ForEach items jitters).
                    HStack(alignment: .center, spacing: 0) {
                        ForEach(clusterOrder, id: \.self) { slot in
                            clusterView(for: slot)
                                .frame(maxWidth: .infinity, alignment: alignment(for: slot))
                        }
                    }
                    .animation(reduceMotion ? nil : .snappy(duration: 0.22, extraBounce: 0.05), value: clusterOrder)
                    .padding(.bottom, 7)

                    // Weight / reps value cards
                    HStack(spacing: 6.5) {
                        CompactValueEditor(
                            label: String(localized: "WEIGHT"),
                            value: currentSet.actualWeight,
                            unit: "kg",
                            icon: "scalemass.fill",
                            isFocused: focusedField == .weight,
                            onTap: {
                                focusedField = .weight
                                WKInterfaceDevice.current().play(.click)
                            }
                        )

                        CompactValueEditor(
                            label: String(localized: "REPS"),
                            value: Binding(
                                get: { Double(currentSet.actualReps.wrappedValue) },
                                set: { currentSet.actualReps.wrappedValue = Int($0) }
                            ),
                            unit: String(localized: "reps"),
                            icon: "repeat",
                            isFocused: focusedField == .reps,
                            onTap: {
                                focusedField = .reps
                                WKInterfaceDevice.current().play(.click)
                            }
                        )
                    }

                    Spacer(minLength: 8)

                    // Fused action row (chevrons + glass Complete button)
                    CompactActionBar(
                        isCompleted: displayedSetIndex < displayedExercise.sets.count
                            ? displayedExercise.sets[displayedSetIndex].isCompleted
                            : false,
                        currentSetIndex: displayedSetIndex,
                        totalSets: totalSets,
                        completedSets: displayedExercise.sets.map { $0.isCompleted },
                        showDoneFlash: showDoneFlash,
                        isFinishing: viewModel.isFinishingSet,
                        isInputEnabled: viewModel.canMutateWorkout,
                        onComplete: { toggleSetCompletion() },
                        onPrevious: { goToPreviousSet() },
                        onNext: { goToNextSet() }
                    )
                    .padding(
                        .bottom,
                        -bottomSafeAreaOverlap(for: geometry.safeAreaInsets.bottom)
                    )
                }
                .padding(.horizontal, 8)
                // Scoped to the content, NOT the navigation container: implicit
                // animations on the stack also animate toolbar/navigation
                // internals, which log "tried to update multiple times per
                // frame" warnings.
                .animation(.easeInOut(duration: 0.2), value: focusedField)
                .animation(.easeInOut(duration: 0.2), value: showDoneFlash)
                .animation(.easeInOut(duration: 0.25), value: viewModel.currentSetIndex)
                .animation(.easeInOut(duration: 0.25), value: viewModel.currentExerciseIndex)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.progress)
            }
        }
        .toolbar {
            // The native back chevron of the shared stack replaces the old
            // custom back button.
            //
            // Only declare the trailing item when it has real content. An
            // empty ToolbarItem still creates a watchOS bar button, which the
            // system forces square (width == height); with zero-width content
            // that contradicts the fixed 37 pt bar-button height and logs
            // "Unable to simultaneously satisfy constraints". Hoisting the
            // condition to the toolbar-content level omits the button entirely
            // in the empty state (e.g. before the first elapsed-time tick).
            if viewModel.isResting && viewModel.isRestTimerMinimized {
                ToolbarItem(placement: .topBarTrailing) {
                    NewShrinkingRestTimer(
                        timeRemaining: viewModel.restTimeRemaining,
                        totalDuration: viewModel.restDuration,
                        onExpand: viewModel.expandRestTimer, onSkip: viewModel.skipRest
                    )
                    .frame(maxWidth: 100, maxHeight: 20)
                    // No .transition here: transitions inside ToolbarItem
                    // builders are unsupported and feed the per-frame
                    // toolbar-update warnings.
                    //
                    // Lift the status onto the system clock's centerline —
                    // toolbar trailing items otherwise sit ~8 pt lower than the
                    // clock (the design has them on one line).
                    .offset(y: -8)
                }
            } else if let elapsedTime = viewModel.elapsedTimeString {
                ToolbarItem(placement: .topBarTrailing) {
                    // Calm elapsed-time capsule chip with tabular digits
                    HStack(spacing: 4) {
                        Image(systemName: "stopwatch")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(OnyxWatch.Colors.textMuted)
                        Text(elapsedTime)
                            .font(.system(size: 10, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(OnyxWatch.Colors.chipText)
                    }
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(OnyxWatch.Colors.chipBackground, in: Capsule())
                    .accessibilityLabel("Elapsed time \(elapsedTime)")
                    .offset(y: -8)
                }
            }
        }
    }

    // MARK: - Subviews

    /// The +/- pair that edits the focused value card. Kept as a single unit so
    /// it can move to the focused card's side without duplicating the buttons.
    private var steppersCluster: some View {
        HStack(spacing: 7) {
            stepperButton("minus", accessibilityLabel: "Decrease") {
                adjustFocusedValue(by: -1)
            }
            stepperButton("plus", accessibilityLabel: "Increase") {
                adjustFocusedValue(by: 1)
            }
        }
    }

    /// Live HR/kCal metrics (only once HealthKit delivers values); occupies the
    /// side opposite the steppers.
    @ViewBuilder
    private var metricsCluster: some View {
        if let heartRate = viewModel.heartRate, let calories = viewModel.activeCalories {
            WorkoutMetricsView(heartRate: heartRate, calories: calories, size: .small)
        }
    }

    private func stepperButton(
        _ systemName: String,
        accessibilityLabel: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: metrics.stepperIconSize, weight: .bold))
                .foregroundStyle(OnyxWatch.Colors.stepperIcon)
                .frame(width: metrics.stepperDiameter, height: metrics.stepperDiameter)
                .background(Circle().fill(OnyxWatch.Colors.stepperGreen))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.92))
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(focusedField == .weight ? String(localized: "Weight") : String(localized: "Reps")))
    }

    // MARK: - Actions

    private func adjustFocusedValue(by amount: Double) {
        switch focusedField {
        case .weight:
            adjustWeight(by: amount)
        case .reps:
            adjustReps(by: Int(amount))
        }
    }

    private func adjustWeight(by amount: Double) {
        let current = currentSet.actualWeight.wrappedValue
        let new = max(0, min(999, current + amount))
        currentSet.actualWeight.wrappedValue = new
    }

    private func adjustReps(by amount: Int) {
        let current = currentSet.actualReps.wrappedValue
        let new = max(0, min(100, current + amount))
        currentSet.actualReps.wrappedValue = new
    }

    private func toggleSetCompletion() {
        guard displayedSetIndex < displayedExercise.sets.count else { return }
        let sets = displayedExercise.sets

        // Completing the last open set of this exercise triggers the brief
        // full-green "Done" celebration on the button.
        let completesExercise = !sets[displayedSetIndex].isCompleted
            && sets.enumerated().allSatisfy { $0.element.isCompleted || $0.offset == displayedSetIndex }

        viewModel.toggleSetCompletion(sets[displayedSetIndex].id, in: displayedExercise.id)

        if completesExercise {
            showDoneFlash = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                showDoneFlash = false
            }
        }
    }

    private func goToPreviousSet() {
        guard displayedSetIndex > 0 else { return }
        viewModel.currentSetIndex = displayedSetIndex - 1
        WKInterfaceDevice.current().play(.click)
    }

    private func goToNextSet() {
        guard displayedSetIndex < totalSets - 1 else { return }
        viewModel.currentSetIndex = displayedSetIndex + 1
        WKInterfaceDevice.current().play(.click)
    }

}
