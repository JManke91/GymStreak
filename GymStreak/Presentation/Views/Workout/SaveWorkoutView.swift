import SwiftUI
import SwiftData

struct SaveWorkoutView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dependencies: AppDependencies
    /// Kept only to pass through to the (out-of-scope) AI Coach recap ViewModel API.
    @Environment(\.modelContext) private var modelContext

    @State private var updateTemplate = true
    @State private var notes = ""
    @State private var syncToHealthKit = true
    @State private var exerciseComparisons: [ExerciseComparisonResult] = []
    @State private var isLoadingComparisons = true
    @State private var recapVM = PostWorkoutRecapViewModel()
    @State private var overloadSheetExercise: WorkoutExercise?

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
                    Button("action.cancel".localized) {
                        // Clean up any orphaned cache entry produced during generation
                        // before the session was persisted via completeWorkout().
                        if let session = viewModel.currentSession {
                            recapVM.discardCachedRecap(for: session)
                        }
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save".localized) {
                        viewModel.completeWorkout(updateTemplate: updateTemplate, notes: notes)
                        dismiss()
                        onSave()
                    }
                }
            }
            .onAppear {
                syncToHealthKit = viewModel.healthKitSyncEnabled
            }
            .task {
                await loadComparisons()
                if let session = viewModel.currentSession {
                    await recapVM.generate(
                        session: session,
                        locale: Locale.current,
                        modelContext: modelContext
                    )
                }
            }
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
                    Task {
                        await recapVM.regenerate(
                            session: session,
                            locale: Locale.current,
                            modelContext: modelContext
                        )
                    }
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
                ForEach(exerciseComparisons, id: \.exerciseName) { comparison in
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
        if let session = viewModel.currentSession {
            exerciseComparisons = dependencies.exerciseProgressService.compareWithPrevious(workout: session)
        }
        isLoadingComparisons = false
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
