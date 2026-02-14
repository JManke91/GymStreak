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
    /// The initial exercise passed in (used as fallback)
    let exercise: ActiveWorkoutExercise
    let onBack: () -> Void
    @EnvironmentObject var viewModel: WatchWorkoutViewModel

    @State private var focusedField: FocusedField = .weight

    enum FocusedField {
        case weight, reps
    }

    init(exercise: ActiveWorkoutExercise, initialSetIndex: Int, onBack: @escaping () -> Void) {
        self.exercise = exercise
        // Note: initialSetIndex is kept for API compatibility but we use viewModel.currentSetIndex
        self.onBack = onBack
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
        NavigationStack {
            ZStack {
                // Background extends edge-to-edge
                OnyxWatch.Colors.background
                    .ignoresSafeArea()

                // Content respects safe areas with explicit padding
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: 8)

                    // CRITICAL CHANGE: Side-by-side layout
                    // Set indicator now appears on top of the NON-focused editor
                    HStack(spacing: 12) {

//                        Image(systemName: "scalemass.fill")
//                                            .font(.system(size: 9, weight: .semibold))
                        // Weight editor (left)
                        CompactValueEditor(
                            label: "WEIGHT",
                            value: currentSet.actualWeight,
                            unit: "kg",
                            icon: "scalemass.fill",
                            step: 1,
                            range: 0...999,
                            isFocused: focusedField == .weight,
                            onTap: {
                                focusedField = .weight
                                WKInterfaceDevice.current().play(.click)
                            },
                            onIncrement: {
                                adjustWeight(by: 1)
                            },
                            onDecrement: {
                                adjustWeight(by: -1)
                            },
                            currentSetIndex: displayedSetIndex,
                            totalSets: totalSets
                        )

                        // Reps editor (right)
                        CompactValueEditor(
                            label: "REPS",
                            value: Binding(
                                get: { Double(currentSet.actualReps.wrappedValue) },
                                set: { currentSet.actualReps.wrappedValue = Int($0) }
                            ),
                            unit: "reps",
                            icon: "repeat",
                            step: 1,
                            range: 0...20,
                            isFocused: focusedField == .reps,
                            onTap: {
                                focusedField = .reps
                                WKInterfaceDevice.current().play(.click)
                            },
                            onIncrement: {
                                adjustReps(by: 1)
                            },
                            onDecrement: {
                                adjustReps(by: -1)
                            },
                            currentSetIndex: displayedSetIndex,
                            totalSets: totalSets
                        )
                    }
                    .padding(.horizontal, 8)

                    Spacer()
                        .frame(height: 5)

                    // Compact action bar (Complete + Prev/Next combined)
                    CompactActionBar(
                        exerciseName: displayedExercise.name,
                        isCompleted: displayedSetIndex < displayedExercise.sets.count
                            ? displayedExercise.sets[displayedSetIndex].isCompleted
                            : false,
                        currentSetIndex: displayedSetIndex,
                        totalSets: totalSets,
                        onComplete: { toggleSetCompletion() },
                        onPrevious: { goToPreviousSet() },
                        onNext: { goToNextSet() },
                        // New: when there's no next set in this exercise, advance to next exercise
                        onAdvance: { goToNextExercise() }
                    )
//                    .frame(height: 30)
//                    .background(Color.red)

//                    Spacer()
//                        .frame(height: 4)
                }
//                .padding(.bottom, 8)
            }
//            .navigationTitle(exercise.name)
//            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        WKInterfaceDevice.current().play(.click)
                        onBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                    }
//                    .accessibilityLabel("Back to exercises")
                }

                // conditionally show rest timer
                // TODO: 🚧 - if no rest timer is shown, show current elapsed time
//                if viewModel.isResting && viewModel.isRestTimerMinimized {
                ToolbarItem(placement: .topBarTrailing) {
                    //                    CompactRestTimer
                    if viewModel.isResting && viewModel.isRestTimerMinimized {

                        NewShrinkingRestTimer(
                            timeRemaining: viewModel.restTimeRemaining,
                            totalDuration: viewModel.restDuration,
                            //                                formattedTime: viewModel.formattedRestTime,
                            onExpand: viewModel.expandRestTimer, onSkip: viewModel.skipRest
                        )
                        //                            .padding(.top, 30)
                        .frame(maxWidth: 100, maxHeight: 20)
                        //                            .listRowIns/*ets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))*/
                        .transition(.move(edge: .top).combined(with: .opacity))
                    } else if let elapsedTime = viewModel.elapsedTimeString {
                        Text(elapsedTime)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: 100, maxHeight: 30)
                    }
                }


                //                }
//                else {
//                    Text("Hello")
//                        .frame(maxWidth: 100, maxHeight: 20)
//                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: focusedField)
        .animation(.easeInOut(duration: 0.25), value: viewModel.currentSetIndex)
        .animation(.easeInOut(duration: 0.25), value: viewModel.currentExerciseIndex)
    }

    // MARK: - Actions

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
        viewModel.toggleSetCompletion(displayedExercise.sets[displayedSetIndex].id, in: displayedExercise.id)
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

    // Advance to the next exercise when current exercise's sets are finished
    private func goToNextExercise() {
        guard viewModel.canGoToNextExercise else { return }
        viewModel.goToNextExercise()
        WKInterfaceDevice.current().play(.click)
    }
}
