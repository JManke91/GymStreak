import SwiftUI
import WatchKit

struct ActiveWorkoutView: View {
    let routineID: UUID

    @EnvironmentObject var viewModel: WatchWorkoutViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab = 0
    @State private var showEndConfirmation = false
    @State private var exercisePath = NavigationPath()

    var body: some View {
        ZStack {
            OnyxWatch.Colors.background.ignoresSafeArea()

            if let summary = viewModel.workoutSummary {
                // Show summary after workout is saved
                WatchWorkoutSummaryView(summary: summary) {
                    viewModel.dismissSummary()
                    dismiss()
                }
            } else {
                // One NavigationStack per presentation context, wrapping the
                // vertical TabView, with the set editor pushed OVER the tabs
                // (Apple's watch workout-app pattern). A stack nested inside
                // tab 0 made two PUIC navigation controllers observe the
                // carousel list ("UIScrollView does not support multiple
                // observers…" assert) and re-triggered per-frame toolbar
                // warnings on every push.
                NavigationStack(path: $exercisePath) {
                    workoutTabs
                        .navigationDestination(for: Int.self) { index in
                            if index < viewModel.exercises.count {
                                FullScreenSetEditorView(exercise: viewModel.exercises[index])
                            }
                        }
                }

                // Overlay full-screen rest timer on top
                if viewModel.isResting && !viewModel.isRestTimerMinimized {
                    NewRestTimerView(
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
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.startWorkout(routineID: routineID)
        }
        // Auto-finish on a workout with modified sets surfaces the same
        // "Update your routine template?" dialog as the manual End flow.
        .onChange(of: viewModel.requestsFinishConfirmation) { _, requested in
            if requested {
                showEndConfirmation = true
                viewModel.requestsFinishConfirmation = false
            }
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
                    }
                }

                Button("Save (Don't Update)") {
                    Task {
                        await viewModel.endWorkout(updateTemplate: false)
                    }
                }
            } else {
                Button("Save Workout") {
                    Task {
                        await viewModel.endWorkout()
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
                // Key "You modified %lld sets. Update your routine template?" carries
                // plural variations in Localizable.xcstrings (en + de).
                Text("You modified \(viewModel.modifiedSetsCount) sets. Update your routine template?")
            } else {
                Text("Save your workout progress?")
            }
        }
    }

    // MARK: - Workout Tabs

    private var workoutTabs: some View {
        TabView(selection: $selectedTab) {
            // Tab 0: Exercise list; tapping a row pushes the set editor onto
            // the enclosing NavigationStack (native slide + edge-swipe back).
            ExerciseListView(
                exercises: viewModel.exercises,
                currentIndex: viewModel.currentExerciseIndex,
                onSelectExercise: { index in
                    viewModel.goToExercise(at: index)
                    exercisePath.append(index)
                },
                onEnd: { showEndConfirmation = true }
            )
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
        // A modally-presented NavigationStack auto-fills its leading toolbar
        // slot with a system close ("X"). Left as the default it dismisses the
        // cover directly — bypassing the End-Workout confirmation and leaving
        // the HealthKit session running (the user could then start a second
        // workout). `.interactiveDismissDisabled()` does NOT remove it (that
        // only governs drag-to-dismiss, which watchOS lacks). Claiming the same
        // `.cancellationAction` slot replaces the system button with our own,
        // routed through the existing Save / Discard / Continue dialog.
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    showEndConfirmation = true
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("End workout")
            }
        }
    }
}

#Preview {
    let routine = WatchRoutine(
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
                order: 0,
                supersetId: nil,
                supersetOrder: 0
            ),
            WatchExercise(
                id: UUID(),
                name: "Shoulder Press",
                muscleGroup: "Shoulders",
                sets: [
                    WatchSet(id: UUID(), reps: 10, weight: 65, restTime: 60),
                    WatchSet(id: UUID(), reps: 10, weight: 65, restTime: 60)
                ],
                order: 1,
                supersetId: nil,
                supersetOrder: 0
            )
        ]
    )
    let store: RoutineStore = {
        let store = RoutineStore(syncState: WatchSyncStateStore())
        store.updateRoutines([routine])
        return store
    }()
    let viewModel = WatchWorkoutViewModel(
        healthKitManager: WatchHealthKitManager(),
        connectivityManager: WatchConnectivityManager.shared,
        routineStore: store
    )

    ActiveWorkoutView(routineID: routine.id)
        .environmentObject(viewModel)
}
