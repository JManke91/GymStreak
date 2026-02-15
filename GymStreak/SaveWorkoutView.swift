import SwiftUI
import SwiftData

struct SaveWorkoutView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var updateTemplate = true
    @State private var notes = ""
    @State private var syncToHealthKit = true
    @State private var exerciseComparisons: [ExerciseComparisonResult] = []
    @State private var isLoadingComparisons = true

    let onSave: () -> Void

    var body: some View {
        NavigationView {
            Form {
                summarySection
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
            let service = ExerciseProgressService(modelContext: modelContext)
            exerciseComparisons = service.compareWithPrevious(workout: session)
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
