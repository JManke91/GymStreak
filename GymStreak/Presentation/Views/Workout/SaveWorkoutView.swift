import SwiftUI
import SwiftData

struct SaveWorkoutView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dependencies: AppDependencies
    /// Kept only to pass through to the (out-of-scope) AI Coach recap ViewModel API.
    @Environment(\.modelContext) private var modelContext
    @Environment(\.weightUnit) private var weightUnit

    @State private var updateTemplate = true
    @State private var notes = ""
    @State private var syncToHealthKit = true
    @State private var exerciseComparisons: [ExerciseComparisonResult] = []
    @State private var isLoadingComparisons = true
    @State private var recapVM = PostWorkoutRecapViewModel()
    @State private var overloadSheetExercise: WorkoutExercise?
    /// True while `completeWorkout` is awaiting the History gate. The sheet stays up for
    /// that wait (see the Save button), so without this a second tap would complete the
    /// workout twice — and the template reconciliation it runs is not idempotent.
    @State private var isSaving = false

    let onSave: () -> Void

    var body: some View {
        NavigationView {
            Form {
                summarySection
                readyForMoreSection
                aiRecapSection
                exerciseProgressSection
                healthKitSection
                templateUpdateSection
                notesSection
            }
            .navigationTitle("save_workout.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Disabled while the commit is in flight, like `EditWorkoutSessionView`:
                    // cancelling mid-wait would discard the recap cache for a session whose
                    // completion is still queued, and the queued task dismisses anyway.
                    Button("action.cancel".localized) {
                        // Clean up any orphaned cache entry produced during generation
                        // before the session was persisted via completeWorkout().
                        if let session = viewModel.currentSession {
                            recapVM.discardCachedRecap(for: session)
                        }
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save".localized) {
                        guard !isSaving else { return }
                        isSaving = true
                        // Dismiss only after the commit lands, mirroring
                        // `EditWorkoutSessionView`: `completeWorkout` is `async` now
                        // (it takes the History gate) and it is what clears
                        // `currentSession`, so `onSave()` must not run against a
                        // half-finished completion.
                        Task {
                            await viewModel.completeWorkout(
                                updateTemplate: updateTemplate,
                                notes: notes
                            )
                            dismiss()
                            onSave()
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear {
                syncToHealthKit = viewModel.healthKitSyncEnabled
            }
            .task {
                // §8 placement B's second trigger, on the completion screen's
                // copy of the suggestion (docs/pro-subscription.md §5g). The
                // ViewModel decides whether this appearance counts; the screen
                // only reports that it appeared. Here rather than in an
                // `.onAppear` on the section: a modifier attached to a `Section`
                // inside a `Form` is not a reliable appearance hook, and this
                // runs before the first `await`, i.e. as the screen appears.
                viewModel.completionOverloadSuggestionsDidAppear()
                await loadComparisons()
                // Re-read rather than reusing a capture from before the await:
                // the workout may have been discarded while the comparison ran.
                if let session = viewModel.currentSession {
                    recapVM.generate(
                        session: session,
                        locale: Locale.current,
                        weightUnit: weightUnit,
                        modelContext: modelContext
                    )
                }
            }
            // The recap is fire-and-forget now, so it outlives this sheet unless it is
            // stopped explicitly — and it must stop the moment the session it describes
            // goes away, which is before `cancelWorkout()` deletes the row.
            //
            // `isSaving` is what separates the two ways `currentSession` goes nil: saving
            // clears it too, and the sheet deliberately stays up for that wait, so a recap
            // still streaming through a save is left alone and `.onDisappear` ends it at
            // dismissal, exactly as the sheet's `.task` cancellation used to.
            .onChange(of: viewModel.currentSession == nil) { _, isGone in
                if isGone && !isSaving { recapVM.cancel() }
            }
            .onDisappear { recapVM.cancel() }
        }
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        Section {
            LabeledContent("save_workout.duration_label".localized) {
                Text(viewModel.formatDuration(viewModel.currentSession?.duration ?? 0))
                    .font(.headline)
            }

            LabeledContent("save_workout.sets_label".localized) {
                let completed = viewModel.currentSession?.completedSetsCount ?? 0
                let total = viewModel.currentSession?.totalSetsCount ?? 0
                let percentage = viewModel.currentSession?.completionPercentage ?? 0
                Text("\(completed)/\(total) (\(percentage)%)")
                    .font(.headline)
                    .foregroundStyle(percentage == 100 ? .green : .primary)
            }

            // Estimated calories
            let estimatedCalories = viewModel.healthKitManager.estimateCaloriesBurned(
                durationInSeconds: viewModel.currentSession?.duration ?? 0
            )
            LabeledContent("save_workout.calories".localized) {
                Text(String(format: "%.0f kcal", estimatedCalories))
                    .font(.headline)
            }
        } header: {
            Text("save_workout.summary".localized)
        }
    }

    // MARK: - AI Recap Section

    @ViewBuilder
    private var aiRecapSection: some View {
        // Only render when the state has content to show.
        // .idle produces a zero-height placeholder so no empty section appears.
        Section {
            AIRecapInline(state: recapVM.state) {
                HapticManager.shared.light()
                if let session = viewModel.currentSession {
                    recapVM.regenerate(
                        session: session,
                        locale: Locale.current,
                        weightUnit: weightUnit,
                        modelContext: modelContext
                    )
                }
            }
        } header: {
            EmptyView()
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    }

    // MARK: - Exercise Progress Section

    @ViewBuilder
    private var exerciseProgressSection: some View {
        if !isLoadingComparisons && !exerciseComparisons.isEmpty {
            Section {
                // Keyed by the workout exercise, not its name: a routine that trains the
                // same exercise twice would otherwise give two rows the same identity.
                ForEach(exerciseComparisons, id: \.workoutExerciseId) { comparison in
                    ExerciseImprovementRow(comparison: comparison)
                }
            } header: {
                Text("save_workout.performance".localized)
            }
        }
    }

    // MARK: - Ready For More Weight Section

    @ViewBuilder
    private var readyForMoreSection: some View {
        // Eligibility (rep goal maxed + persistable template target, swap-aware)
        // lives in the ViewModel — see overloadSuggestionExercises.
        let exercises = viewModel.overloadSuggestionExercises

        if !exercises.isEmpty {
            Section {
                ForEach(exercises, id: \.id) { exercise in
                    ProgressiveOverloadCard(
                        exercise: exercise,
                        libraryExercise: viewModel.performedExercise(for: exercise),
                        canUndo: viewModel.canUndoProgressiveOverload(for: exercise),
                        // An applied increase no longer bumps the workout's own
                        // sets, so the confirmed row is told the new template
                        // weight rather than reading it off them.
                        appliedWeight: viewModel.appliedOverloadWeight(for: exercise),
                        hasAmbiguousAppliedWeight: viewModel.hasNonUniformAppliedOverload(for: exercise),
                        // The CTA strikes through what an increase starts from:
                        // the template, which the picker also previews.
                        templateWeight: viewModel.overloadTemplateFirstSet(for: exercise)?.weight,
                        onIncrease: { overloadSheetExercise = exercise },
                        onUndo: {
                            withAnimation(DesignSystem.Animation.spring) {
                                viewModel.undoProgressiveOverload(for: exercise)
                            }
                        }
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowSeparator(.hidden)
                }
            } header: {
                readyForMoreHeader(exercises: exercises)
            }
            .sheet(item: $overloadSheetExercise) { exercise in
                WeightIncreaseSheet(
                    workoutExercise: exercise,
                    // Preview the template values the apply actually raises.
                    templateFirstSet: viewModel.overloadTemplateFirstSet(for: exercise),
                    onApply: { increment in
                        withAnimation(DesignSystem.Animation.spring) {
                            viewModel.applyProgressiveOverload(for: exercise, weightIncrement: increment)
                        }
                        overloadSheetExercise = nil
                        HapticManager.shared.success()
                    },
                    onCancel: { overloadSheetExercise = nil }
                )
            }
        }
    }

    private func readyForMoreHeader(exercises: [WorkoutExercise]) -> some View {
        let pending = exercises.filter { !$0.progressiveOverloadApplied }.count
        let anyApplied = exercises.contains { $0.progressiveOverloadApplied }
        let badgeColor: Color = anyApplied ? DesignSystem.Colors.tint : .orange

        return HStack(spacing: 8) {
            Image(systemName: "arrow.up")
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)

            Text("rep_range.ready_for_more".localized)

            Spacer()

            if pending > 0 {
                Text("\(pending)")
                    .font(.caption.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 7)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(badgeColor.opacity(0.2), in: Capsule())
            }
        }
    }

    // MARK: - HealthKit Section

    @ViewBuilder
    private var healthKitSection: some View {
        if viewModel.healthKitManager.isHealthKitAvailable {
            Section {
                Toggle(isOn: $syncToHealthKit) {
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                        Text("save_workout.apple_health".localized)
                    }
                }
                .onChange(of: syncToHealthKit) { _, newValue in
                    viewModel.setHealthKitSyncEnabled(newValue)
                }
            } footer: {
                Text("save_workout.apple_health_footer".localized)
            }
        }
    }

    // MARK: - Template Update Section

    private var templateUpdateSection: some View {
        Section {
            Toggle("save_workout.update_template".localized, isOn: $updateTemplate)
        } footer: {
            Text("save_workout.update_template_footer".localized)
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        Section {
            TextField("save_workout.notes_placeholder".localized, text: $notes, axis: .vertical)
                .lineLimit(3...6)
        } header: {
            Text("save_workout.notes".localized)
        }
    }

    // MARK: - Data Loading

    private func loadComparisons() async {
        guard let session = viewModel.currentSession else {
            isLoadingComparisons = false
            return
        }
        let results = await dependencies.exerciseProgressService
            .compareWithPrevious(workout: session)
        // `cancelWorkout()` can discard the workout while the history scan runs. It
        // unpublishes `currentSession` before deleting the row, and both happen on this
        // actor, so a resume that still sees the same object is a resume that came before
        // the delete — the proof `WorkoutDetailView.isBeingDeleted` provides there. The
        // results themselves are values; publishing them for a workout the user just threw
        // away would render a section about a session that no longer exists.
        isLoadingComparisons = false
        guard viewModel.currentSession === session else { return }
        exerciseComparisons = results
    }
}

// MARK: - Exercise Improvement Row

private struct ExerciseImprovementRow: View {
    let comparison: ExerciseComparisonResult

    var body: some View {
        HStack {
            Text(comparison.exerciseName)
                .font(.subheadline)

            Spacer()

            if comparison.isFirstTime {
                Text("save_workout.new_exercise".localized)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DesignSystem.Colors.tint)
            } else if let percentage = comparison.volumeDeltaPercentage {
                DeltaBadge(value: percentage, unit: "%", isWeight: true)
            } else {
                Text("-")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
