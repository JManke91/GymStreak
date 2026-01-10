import SwiftUI

struct SaveWorkoutView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var updateTemplate = false
    @State private var notes = ""
    @State private var syncToHealthKit = true

    let onSave: () -> Void

    var body: some View {
        NavigationView {
            Form {
                // Summary Section
                Section {
                    LabeledContent("save_workout.duration_label".localized) {
                        Text(viewModel.formatDuration(viewModel.currentSession?.duration ?? 0))
                            .font(.headline)
                    }

                    LabeledContent("save_workout.sets_completed_label".localized) {
                        Text("\(viewModel.currentSession?.completedSetsCount ?? 0)")
                            .font(.headline)
                    }

                    LabeledContent("save_workout.total_volume".localized) {
                        Text(String(format: "%.1f kg", viewModel.currentSession?.totalVolume ?? 0))
                            .font(.headline)
                    }

                    if let percentage = viewModel.currentSession?.completionPercentage {
                        LabeledContent("save_workout.completion".localized) {
                            Text("\(percentage)%")
                                .font(.headline)
                                .foregroundStyle(percentage == 100 ? .green : .primary)
                        }
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

                // HealthKit Sync Section
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

                // Template Update Section
                Section {
                    Toggle("save_workout.update_template".localized, isOn: $updateTemplate)
                } footer: {
                    Text("save_workout.update_template_footer".localized)
                }

                // Notes Section
                Section {
                    TextField("save_workout.notes_placeholder".localized, text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("save_workout.notes".localized)
                }
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
        }
    }
}
