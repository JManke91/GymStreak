import SwiftUI
import WatchKit

enum WorkoutRoute: Hashable {
    case setEditor(slotID: UUID)
    case exerciseCatalogue
    case configureExercise(exerciseID: UUID)
}

private struct PendingExerciseRemoval: Identifiable {
    let slotID: UUID
    let name: String
    let completedSetCount: Int

    var id: UUID { slotID }
}

struct ActiveWorkoutView: View {
    let routineID: UUID

    @EnvironmentObject var viewModel: WatchWorkoutViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab = 0
    @State private var showEndConfirmation = false
    @State private var exercisePath: [WorkoutRoute] = []
    @State private var pendingRemoval: PendingExerciseRemoval?
    /// The minimized rest pill grown into its inline ± stepper. Owned here, not
    /// by the overlay, because the grown pill reaches across the top of whatever
    /// screen is below it — the workout screens read it from the environment and
    /// fade the content it covers.
    @State private var isRestStepperOpen = false

    var body: some View {
        ZStack {
            OnyxWatch.Colors.background.ignoresSafeArea()

            if let summary = viewModel.workoutSummary {
                // Show summary after workout is saved. Teardown (dismissSummary)
                // is deferred to the cover's onDismiss so the summary stays
                // visible during the slide-away instead of the view clearing its
                // state mid-dismiss and flashing the empty active-workout list.
                WatchWorkoutSummaryView(summary: summary) {
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
                        .navigationDestination(for: WorkoutRoute.self) { route in
                            switch route {
                            case .setEditor(let slotID):
                                if let exercise = viewModel.exercise(slotID: slotID) {
                                    FullScreenSetEditorView(exercise: exercise)
                                } else {
                                    unavailableDestination("Exercise no longer available")
                                }

                            case .exerciseCatalogue:
                                WorkoutExerciseCatalogView { item in
                                    viewModel.beginExerciseConfiguration(item: item)
                                    exercisePath.append(.configureExercise(exerciseID: item.id))
                                }

                            case .configureExercise(let exerciseID):
                                if let selection = viewModel.pendingExerciseSelection,
                                   selection.exerciseID == exerciseID {
                                    WatchExerciseConfigurationView(selection: selection) {
                                        exercisePath.removeAll()
                                    }
                                } else {
                                    unavailableDestination("Exercise no longer available")
                                }
                            }
                        }
                }
                .environment(\.isRestPillStepperOpen, isRestStepperOpen)

                // The one and only rest timer of the active workout, in BOTH of
                // its states. Owned here — a sibling of the NavigationStack —
                // so exactly one instance is ever mounted (the vertical TabView
                // keeps neighbouring pages alive, so per-page copies used to be
                // mounted simultaneously) and so the minimized pill layers above
                // a pushed set editor. Large and minimized therefore share one
                // coordinate space, which is what the morph needs.
                WorkoutRestTimerOverlay(isStepperOpen: $isRestStepperOpen)
            }
        }
        // The whole progressive-overload flow, as ONE modal sheet. On watchOS a
        // sheet is always modal, so it blocks taps reaching the live set
        // controls underneath — the floating card this replaced did not.
        // Dismissing it (swipe / crown) means "Later": the user is mid-workout
        // and must never be trapped, and deferring is already a first-class
        // outcome that preserves the post-workout summary opportunity.
        .sheet(
            isPresented: Binding(
                get: { viewModel.overloadPresentation.isActive },
                set: { isPresented in
                    guard !isPresented, let slotID = viewModel.overloadPresentation.slotID else { return }
                    viewModel.deferProgressiveOverloadIfPresenting(slotID: slotID)
                }
            )
        ) {
            ProgressiveOverloadSheet()
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.startWorkout(routineID: routineID)
        }
        // Auto-finish on a workout with modified sets surfaces the same
        // "Update your routine template?" dialog as the manual End flow.
        .onChange(of: viewModel.requestsFinishConfirmation) { _, requested in
            if requested {
                viewModel.requestsFinishConfirmation = false
                requestEndConfirmation()
            }
        }
        .onChange(of: exercisePath) { _, path in
            let isInCatalogue = path.contains(.exerciseCatalogue)
            let isConfiguring = path.contains { route in
                if case .configureExercise = route { return true }
                return false
            }
            viewModel.updateExerciseEditingState(
                isInCatalogueFlow: isInCatalogue,
                isConfiguring: isConfiguring
            )
        }
        .onChange(of: viewModel.workoutSummary != nil) { _, hasSummary in
            if hasSummary {
                exercisePath.removeAll()
                pendingRemoval = nil
            }
        }
        .confirmationDialog(
            "End Workout?",
            isPresented: $showEndConfirmation,
            titleVisibility: .visible
        ) {
            if viewModel.hasTemplateChanges {
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
                // Only dismiss here — the actual discard (HealthKit teardown +
                // state reset) runs in the cover's onDismiss once it's off
                // screen, so the cleared state can't flash the empty
                // active-workout list during the dismiss animation.
                dismiss()
            }

            Button("Continue", role: .cancel) { }
        } message: {
            switch viewModel.finishDialogState {
            case .combined(let modifiedSetCount):
                Text("You modified \(modifiedSetCount) sets and changed exercises. Update your routine template?")
            case .structuralOnly:
                Text("You changed the exercises in this workout. Update your routine template?")
            case .setsOnly(let count):
                Text("You modified \(count) sets. Update your routine template?")
            case .unchanged:
                Text("Save your workout progress?")
            }
        }
        .confirmationDialog(
            "Remove Exercise?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { removal in
            Button("Remove \(removal.name)", role: .destructive) {
                _ = viewModel.removeExercise(slotID: removal.slotID)
                exercisePath.removeAll { route in
                    if case .setEditor(let slotID) = route { return slotID == removal.slotID }
                    return false
                }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { removal in
            if removal.completedSetCount > 0 {
                Text("Removing \(removal.name) also removes its \(removal.completedSetCount) completed sets from this workout's saved history.")
            } else {
                Text("Remove \(removal.name) from this workout?")
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
                onSelectExercise: { slotID in
                    viewModel.goToExercise(slotID: slotID)
                    exercisePath.append(.setEditor(slotID: slotID))
                },
                onAddExercise: {
                    viewModel.beginExerciseCatalogue()
                    exercisePath.append(.exerciseCatalogue)
                },
                onRequestRemoval: { exercise in
                    showEndConfirmation = false
                    pendingRemoval = PendingExerciseRemoval(
                        slotID: exercise.id,
                        name: exercise.name,
                        completedSetCount: exercise.completedSetsCount
                    )
                },
                onEnd: requestEndConfirmation
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
                onEnd: requestEndConfirmation
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
                    requestEndConfirmation()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("End workout")
            }
        }
    }

    private func requestEndConfirmation() {
        pendingRemoval = nil
        viewModel.prepareForTerminalPresentation()
        exercisePath.removeAll()
        Task { @MainActor in
            await Task.yield()
            showEndConfirmation = true
        }
    }

    private func unavailableDestination(_ message: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
    }
}
