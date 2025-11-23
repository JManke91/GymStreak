import SwiftUI
import WatchKit

struct ActiveWorkoutView: View {
    let routine: WatchRoutine

    @EnvironmentObject var viewModel: WatchWorkoutViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab = 0
    @State private var showEndConfirmation = false
    @State private var exercisePath = NavigationPath()

    private var isShowingExerciseDetail: Bool {
        !exercisePath.isEmpty
    }

    var body: some View {
        ZStack {
            // Black background for entire workout view
            Color.black.ignoresSafeArea()

            // Keep workoutTabs always in hierarchy to preserve navigation state
            workoutTabs
                .overlay {
                    // Overlay full-screen timer on top
                    if viewModel.isResting && !viewModel.isRestTimerMinimized {
                        RestTimerView(
                            timeRemaining: viewModel.restTimeRemaining,
                            totalDuration: viewModel.restDuration,
                            formattedTime: viewModel.formattedRestTime,
                            state: viewModel.restTimerState,
                            onSkip: viewModel.skipRest,
                            onMinimize: viewModel.minimizeRestTimer
                        )
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: viewModel.isResting)
                .animation(.easeInOut(duration: 0.25), value: viewModel.isRestTimerMinimized)
                .animation(.easeInOut(duration: 0.3), value: viewModel.restTimerState)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.startWorkout(with: routine)
        }
        .confirmationDialog(
            "End Workout?",
            isPresented: $showEndConfirmation,
            titleVisibility: .visible
        ) {
            if viewModel.hasModifiedSets {
                Button("Save & Update Template") {
                    Task {
                        await viewModel.endWorkout(updateTemplate: true)
                        dismiss()
                    }
                }

                Button("Save (Don't Update)") {
                    Task {
                        await viewModel.endWorkout(updateTemplate: false)
                        dismiss()
                    }
                }
            } else {
                Button("Save Workout") {
                    Task {
                        await viewModel.endWorkout()
                        dismiss()
                    }
                }
            }

            Button("Discard", role: .destructive) {
                viewModel.discardWorkout()
                dismiss()
            }

            Button("Continue", role: .cancel) { }
        } message: {
            if viewModel.hasModifiedSets {
                Text("You modified \(viewModel.modifiedSetsCount) set\(viewModel.modifiedSetsCount == 1 ? "" : "s"). Update your routine template?")
            } else {
                Text("Save your workout progress?")
            }
        }
    }

    // MARK: - Workout Tabs

    private var workoutTabs: some View {
        TabView(selection: $selectedTab) {
            // Tab 0: Exercise flow with state-based navigation
            ZStack {
                if isShowingExerciseDetail, let exercise = viewModel.currentExercise {
                    NavigationStack {
                        SetListView(
                            exercise: exercise,
                            progress: viewModel.progress,
                            completedSets: viewModel.completedSetsCount,
                            totalSets: viewModel.totalSetsCount
                        )
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button {
                                    WKInterfaceDevice.current().play(.click)
                                    withAnimation {
                                        exercisePath.removeLast()
                                    }
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 18, weight: .semibold))
                                }
                            }
                        }
                    }
                    .transition(.move(edge: .trailing))
                    .gesture(
                        DragGesture()
                            .onEnded { gesture in
                                if gesture.translation.width > 50 {
                                    WKInterfaceDevice.current().play(.click)
                                    withAnimation {
                                        exercisePath.removeLast()
                                    }
                                }
                            }
                    )
                } else {
                    ExerciseListView(
                        exercises: viewModel.exercises,
                        currentIndex: viewModel.currentExerciseIndex,
                        onSelectExercise: { index in
                            viewModel.goToExercise(at: index)
                            withAnimation {
                                exercisePath.append(index)
                            }
                        },
                        onEnd: { showEndConfirmation = true }
                    )
                    .transition(.move(edge: .leading))
                }
            }
            .tag(0)

            // Tab 1: HealthKit Metrics
            MetricsView(
                elapsedTime: viewModel.formattedElapsedTime,
                heartRate: viewModel.heartRate,
                calories: viewModel.activeCalories
            )
            .tag(1)

            // Tab 2: Controls
            ControlsView(
                isPaused: viewModel.isPaused,
                onPause: viewModel.pauseWorkout,
                onResume: viewModel.resumeWorkout,
                onEnd: { showEndConfirmation = true }
            )
            .tag(2)
        }
        .tabViewStyle(.verticalPage)
    }
}

#Preview {
    ActiveWorkoutView(
        routine: WatchRoutine(
            id: UUID(),
            name: "Push Day",
            exercises: [
                WatchExercise(
                    id: UUID(),
                    name: "Bench Press",
                    muscleGroup: "Chest",
                    sets: [
                        WatchSet(id: UUID(), reps: 10, weight: 135, restTime: 90),
                        WatchSet(id: UUID(), reps: 10, weight: 135, restTime: 90)
                    ],
                    order: 0
                ),
                WatchExercise(
                    id: UUID(),
                    name: "Shoulder Press",
                    muscleGroup: "Shoulders",
                    sets: [
                        WatchSet(id: UUID(), reps: 10, weight: 65, restTime: 60),
                        WatchSet(id: UUID(), reps: 10, weight: 65, restTime: 60)
                    ],
                    order: 1
                )
            ]
        )
    )
    .environmentObject(WatchWorkoutViewModel(
        healthKitManager: WatchHealthKitManager(),
        connectivityManager: WatchConnectivityManager.shared
    ))
}
