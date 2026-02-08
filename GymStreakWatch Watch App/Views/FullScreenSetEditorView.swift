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
    let exercise: ActiveWorkoutExercise
    let onBack: () -> Void
    @EnvironmentObject var viewModel: WatchWorkoutViewModel

    @State private var focusedField: FocusedField = .weight
    @State private var currentSetIndex: Int

    enum FocusedField {
        case weight, reps
    }

    init(exercise: ActiveWorkoutExercise, initialSetIndex: Int, onBack: @escaping () -> Void) {
        self.exercise = exercise
        self._currentSetIndex = State(initialValue: initialSetIndex)
        self.onBack = onBack
    }

    private var currentSet: Binding<ActiveWorkoutSet> {
        Binding(
            get: { exercise.sets[currentSetIndex] },
            set: { updatedSet in
                viewModel.updateSet(updatedSet, in: exercise.id)
            }
        )
    }

    private var totalSets: Int {
        exercise.sets.count
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
                            currentSetIndex: currentSetIndex,
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
                            currentSetIndex: currentSetIndex,
                            totalSets: totalSets
                        )
                    }
                    .padding(.horizontal, 8)

                    Spacer()
                        .frame(height: 5)

                    // Compact action bar (Complete + Prev/Next combined)
                    CompactActionBar(
                        exerciseName: exercise.name, // changed: use the actual exercise name instead of dummy string
                        isCompleted: exercise.sets[currentSetIndex].isCompleted,
                        currentSetIndex: currentSetIndex,
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
        .animation(.easeInOut(duration: 0.25), value: currentSetIndex)
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
        viewModel.toggleSetCompletion(exercise.sets[currentSetIndex].id, in: exercise.id)
    }

    private func goToPreviousSet() {
        guard currentSetIndex > 0 else { return }
        currentSetIndex -= 1
        viewModel.currentSetIndex = currentSetIndex // Keep ViewModel in sync
        WKInterfaceDevice.current().play(.click)
    }

    private func goToNextSet() {
        guard currentSetIndex < totalSets - 1 else { return }
        currentSetIndex += 1
        viewModel.currentSetIndex = currentSetIndex // Keep ViewModel in sync
        WKInterfaceDevice.current().play(.click)
    }

    // New: Advance to the next exercise when current exercise's sets are finished
    private func goToNextExercise() {
        guard viewModel.canGoToNextExercise else { return }
        // Ask the ViewModel to move to the next exercise (it sets its currentSetIndex appropriately)
        viewModel.goToNextExercise()
        // Sync local state to ViewModel
        currentSetIndex = viewModel.currentSetIndex
        WKInterfaceDevice.current().play(.click)
    }
}
