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
                Color.black
                    .ignoresSafeArea()

                // Content respects safe areas with explicit padding
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: 8)

                    // CRITICAL CHANGE: Side-by-side layout
                    // Set indicator now appears on top of the NON-focused editor
                    HStack(spacing: 12) {
                        // Weight editor (left)
                        CompactValueEditor(
                            label: "WEIGHT",
                            value: currentSet.actualWeight,
                            unit: "lb",
                            icon: "scalemass.fill",
                            step: 5,
                            range: 0...999,
                            isFocused: focusedField == .weight,
                            onTap: {
                                focusedField = .weight
                                WKInterfaceDevice.current().play(.click)
                            },
                            onIncrement: {
                                adjustWeight(by: 5)
                            },
                            onDecrement: {
                                adjustWeight(by: -5)
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
                            range: 0...100,
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
                        .frame(height: 4)

                    // Compact action bar (Complete + Prev/Next combined)
                    CompactActionBar(
                        isCompleted: exercise.sets[currentSetIndex].isCompleted,
                        currentSetIndex: currentSetIndex,
                        totalSets: totalSets,
                        onComplete: { toggleSetCompletion() },
                        onPrevious: { goToPreviousSet() },
                        onNext: { goToNextSet() }
                    )

                    Spacer()
                        .frame(height: 4)
                }
                .padding(.bottom, 8)
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        WKInterfaceDevice.current().play(.click)
                        onBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .accessibilityLabel("Back to exercises")
                }
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
}

// MARK: - Preview

//#Preview {
//    FullScreenSetEditorView(
//        exercise: ActiveWorkoutExercise(
//            id: UUID(),
//            name: "Bench Press",
//            muscleGroup: "Chest",
//            sets: [
//                ActiveWorkoutSet(
//                    id: UUID(),
//                    plannedReps: 10,
//                    actualReps: 10,
//                    plannedWeight: 135,
//                    actualWeight: 135,
//                    restTime: 90,
//                    isCompleted: true,
//                    completedAt: Date(),
//                    order: 0
//                ),
//                ActiveWorkoutSet(
//                    id: UUID(),
//                    plannedReps: 10,
//                    actualReps: 10,
//                    plannedWeight: 140,
//                    actualWeight: 140,
//                    restTime: 90,
//                    isCompleted: false,
//                    completedAt: nil,
//                    order: 1
//                ),
//                ActiveWorkoutSet(
//                    id: UUID(),
//                    plannedReps: 10,
//                    actualReps: 10,
//                    plannedWeight: 135,
//                    actualWeight: 135,
//                    restTime: 90,
//                    isCompleted: false,
//                    completedAt: nil,
//                    order: 2
//                ),
//                ActiveWorkoutSet(
//                    id: UUID(),
//                    plannedReps: 10,
//                    actualReps: 10,
//                    plannedWeight: 135,
//                    actualWeight: 135,
//                    restTime: 90,
//                    isCompleted: false,
//                    completedAt: nil,
//                    order: 3
//                )
//            ],
//            order: 0
//        ),
//        initialSetIndex: 1,
//        onBack: {}
//    )
//    .environmentObject(WatchWorkoutViewModel(
//        healthKitManager: WatchHealthKitManager(),
//        connectivityManager: WatchConnectivityManager.shared
//    ))
//}
