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
    /// The Crown steps the focused card only while this is true. Armed by a tap
    /// on a card, so a brushed Crown can never change a value on its own.
    @State private var isCrownUnlocked = false
    /// Bumped by every unlocking tap so switching cards restarts the relock delay.
    @State private var crownArmingID = 0
    /// When the unlocked Crown locks again — drives the card's draining border.
    @State private var crownRelockDeadline: Date?
    /// "Tap first" on the focused card, answering a Crown turned while locked.
    @State private var showsCrownHint = false
    @State private var crownHintTask: Task<Void, Never>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.weightUnit) private var weightUnit
    @Environment(\.isRestPillStepperOpen) private var isRestPillStepperOpen
    @Environment(\.isCoveredByRestTimer) private var isCoveredByRestTimer

    private let metrics = WorkoutScreenMetrics.current
    /// Detents a locked rotation must reach before "Tap first" shows — a single
    /// brushed detent is not an attempt to use the Crown.
    private static let crownHintMinimumDetents = 2
    /// How long "Tap first" stays after the last locked detent.
    private static let crownHintLife: Duration = .milliseconds(1500)

    enum FocusedField {
        case weight, reps
    }

    /// Stable identities for the two items in the steppers/metrics row. Keying
    /// the ForEach on these (never on position) is what lets SwiftUI animate the
    /// focus swap as a slide instead of a crossfade.
    private enum ClusterSlot: Hashable {
        case steppers, metrics
    }

    /// A tap could hand the Crown to a card right now: neither rest-timer
    /// candidate holds it and the workout can change.
    private var canUnlockCrown: Bool {
        !isCoveredByRestTimer
            && !isRestPillStepperOpen
            && viewModel.canMutateWorkout
    }

    /// The editor's half of the single-owner Crown model
    /// (`docs/watch-rest-timer-ui.md` "Crown ownership"): it may take the Crown
    /// only while unlocked AND neither rest-timer candidate holds it.
    private var ownsCrown: Bool {
        isCrownUnlocked && canUnlockCrown
    }

    private func crownState(for field: FocusedField) -> CompactValueEditor.CrownState {
        guard focusedField == field, canUnlockCrown else { return .unavailable }
        return ownsCrown ? .unlocked : .locked
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

    var body: some View {
        // No NavigationStack of its own: this view is pushed onto the shared
        // stack owned by ActiveWorkoutView. A second stack created mid-swap
        // fed "ToolbarReader/navigationEventHandlers tried to update multiple
        // times per frame" warnings.
        GeometryReader { _ in
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
                    // Top zone: routine level ("Exercise X / Y" + neutral
                    // segment bar) and exercise level (name + "Set X/Y") (design §4).
                    WorkoutTopProgressView(
                        exerciseName: displayedExercise.name,
                        exerciseIndex: viewModel.currentExerciseIndex,
                        exerciseCount: viewModel.exercises.count,
                        setIndex: displayedSetIndex,
                        setCount: totalSets,
                        exerciseProgress: viewModel.progressSegments
                    ) {
                        topTrailingAccessory
                    }
                    .padding(.horizontal, 2)

                    Spacer(minLength: metrics.editorTopGap)

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
                    .padding(.bottom, metrics.clusterBottomGap)

                    // Weight / reps value cards
                    HStack(spacing: metrics.valueCardGap) {
                        CompactValueEditor(
                            label: String(localized: "WEIGHT"),
                            value: WatchWeightFormatting.number(
                                currentSet.actualWeight.wrappedValue, in: weightUnit
                            ),
                            unit: WatchWeightFormatting.unitWord(weightUnit),
                            spokenUnit: WatchWeightFormatting.spokenUnitWord(weightUnit),
                            icon: "scalemass.fill",
                            isFocused: focusedField == .weight,
                            crownState: crownState(for: .weight),
                            crownRelockDeadline: crownRelockDeadline,
                            showsCrownHint: showsCrownHint && canUnlockCrown && focusedField == .weight,
                            onTap: { selectCard(.weight) },
                            onAdjust: { adjust(.weight, by: $0) }
                        )

                        CompactValueEditor(
                            label: String(localized: "REPS"),
                            value: String(currentSet.actualReps.wrappedValue),
                            unit: String(localized: "reps"),
                            spokenUnit: String(localized: "reps"),
                            icon: "repeat",
                            isFocused: focusedField == .reps,
                            crownState: crownState(for: .reps),
                            crownRelockDeadline: crownRelockDeadline,
                            showsCrownHint: showsCrownHint && canUnlockCrown && focusedField == .reps,
                            onTap: { selectCard(.reps) },
                            onAdjust: { adjust(.reps, by: $0) }
                        )
                    }

                    Spacer(minLength: metrics.editorBottomGap)

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
                    // Sits within the bottom safe area so the side chevrons stay
                    // clear of the watch's rounded corners (an earlier negative
                    // overlap pushed the row past the edge and clipped them).
                }
                .padding(.horizontal, 8)
                // Scoped to the content, NOT the navigation container: implicit
                // animations on the stack also animate toolbar/navigation
                // internals, which log "tried to update multiple times per
                // frame" warnings.
                .animation(.easeInOut(duration: 0.2), value: focusedField)
                .animation(.easeInOut(duration: 0.2), value: ownsCrown)
                .animation(.easeInOut(duration: 0.15), value: showsCrownHint)
                .animation(.easeInOut(duration: 0.2), value: showDoneFlash)
                .animation(.easeInOut(duration: 0.25), value: viewModel.currentSetIndex)
                .animation(.easeInOut(duration: 0.25), value: viewModel.currentExerciseIndex)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.progress)
                .setValueCrownInput(
                    isListening: canUnlockCrown,
                    isActive: ownsCrown,
                    isUnlocked: $isCrownUnlocked,
                    armingID: crownArmingID,
                    onDetents: applyCrownDetents,
                    onCommit: viewModel.commitSetValueAdjustment,
                    onLockedTurn: showCrownHintIfNeeded,
                    onRelockScheduled: { crownRelockDeadline = $0 }
                )
            }
        }
        // Every hand-off away from this set re-locks; the editor gets the Crown
        // back only through a fresh tap.
        .onChange(of: viewModel.currentSetIndex) { _, _ in lockCrown() }
        .onChange(of: viewModel.currentExerciseIndex) { _, _ in lockCrown() }
        .onChange(of: viewModel.isResting) { _, _ in lockCrown() }
        // Losing ownership for ANY reason (pill stepper opening, a minimized
        // rest expanding to the large timer, mutation suspended) re-locks too,
        // so ownership coming back never hands the Crown back on its own.
        .onChange(of: ownsCrown) { _, owns in if !owns { lockCrown() } }
        .onDisappear {
            lockCrown()
            crownHintTask?.cancel()
        }
    }

    // MARK: - Subviews

    /// Right-aligned accessory on the routine label's line: the elapsed-time
    /// label, moved here from the top toolbar (design 2026-07-24) so it no longer
    /// collides with the system clock.
    ///
    /// While the rest timer is minimized this slot stays EMPTY: the single
    /// minimized pill is owned by ActiveWorkoutView and overlays this screen from
    /// the same corner, so the two would otherwise stack on top of each other.
    @ViewBuilder
    private var topTrailingAccessory: some View {
        if !(viewModel.isResting && viewModel.isRestTimerMinimized),
           let elapsedTime = viewModel.elapsedTimeString {
            // Large bold elapsed-time label with a stopwatch glyph (no capsule).
            // WorkoutTopProgressView places this as a baseline-pinned overlay, so
            // its extra height grows upward into the free status-bar space with
            // zero effect on the row height — no negative-inset math. The icon is
            // baselined against the digits (Apple's documented SF-Symbol-vs-Text
            // alignment pattern).
            HStack(alignment: .firstTextBaseline, spacing: 3.5) {
                Image(systemName: "stopwatch")
                    .font(.system(size: metrics.elapsedIconSize, weight: .medium))
                    .foregroundStyle(OnyxWatch.Colors.textMuted)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 0.1 * $0.height }
                Text(elapsedTime)
                    .font(.system(size: metrics.elapsedFontSize, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color(white: 0.9))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Elapsed time \(elapsedTime)")
        }
    }

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

    /// Focuses the card and unlocks the Crown for it — unless the Crown cannot
    /// be unlocked right now (rest timer holds it, mutation suspended). A tap on the card that
    /// is already unlocked locks it again: the lock glyph toggles both ways.
    private func selectCard(_ field: FocusedField) {
        if field == focusedField && ownsCrown {
            lockCrown()
        } else {
            focusedField = field
            // `canUnlockCrown`, not just `canMutateWorkout`: unlocking while a
            // rest-timer candidate holds the Crown would hand it back unlocked,
            // without a fresh tap, the moment that candidate lets go.
            if canUnlockCrown {
                isCrownUnlocked = true
                crownArmingID += 1
                hideCrownHint()
            }
        }
        WKInterfaceDevice.current().play(.click)
    }

    private func lockCrown() {
        isCrownUnlocked = false
        crownRelockDeadline = nil
    }

    /// Answers a Crown turned while locked: never a value change, only "Tap
    /// first" on the focused card, kept up for as long as the turning goes on.
    private func showCrownHintIfNeeded(lockedDetents: Int) {
        guard abs(lockedDetents) >= Self.crownHintMinimumDetents else { return }
        showsCrownHint = true
        crownHintTask?.cancel()
        crownHintTask = Task { @MainActor in
            try? await Task.sleep(for: Self.crownHintLife)
            guard !Task.isCancelled else { return }
            showsCrownHint = false
        }
    }

    private func hideCrownHint() {
        crownHintTask?.cancel()
        showsCrownHint = false
    }

    private func adjustFocusedValue(by amount: Int) {
        adjust(focusedField, by: amount)
    }

    /// The ± path (and VoiceOver's swipe): confirmed with a haptic, checkpointed.
    private func adjust(_ field: FocusedField, by amount: Int) {
        currentSet.wrappedValue = stepped(currentSet.wrappedValue, field: field, by: amount)
    }

    /// The Crown writes through the silent, non-checkpointing path; the
    /// checkpoint is taken once per rotation via `onCommit`.
    private func applyCrownDetents(_ detents: Int) {
        viewModel.adjustSetValue(
            stepped(currentSet.wrappedValue, field: focusedField, by: detents),
            in: displayedExercise.id
        )
    }

    /// One stepping rule for ± and the Crown — `WatchSetValueStepping` keeps
    /// the weight unsnapped in display space (see its doc comment).
    private func stepped(_ set: ActiveWorkoutSet, field: FocusedField, by steps: Int) -> ActiveWorkoutSet {
        var set = set
        switch field {
        case .weight:
            set.actualWeight = WatchSetValueStepping.weight(set.actualWeight, steppedBy: steps, in: weightUnit)
        case .reps:
            set.actualReps = WatchSetValueStepping.reps(set.actualReps, steppedBy: steps)
        }
        return set
    }

    private func toggleSetCompletion() {
        guard displayedSetIndex < displayedExercise.sets.count else { return }
        let sets = displayedExercise.sets

        // Completing the last open set of this exercise triggers the brief
        // full-green "Done" celebration on the button.
        let completesExercise = !sets[displayedSetIndex].isCompleted
            && sets.enumerated().allSatisfy { $0.element.isCompleted || $0.offset == displayedSetIndex }

        lockCrown()
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
