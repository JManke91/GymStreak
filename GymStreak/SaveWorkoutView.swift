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
                    LabeledContent("Duration") {
                        Text(viewModel.formatDuration(viewModel.currentSession?.duration ?? 0))
                            .font(.headline)
                    }

                    LabeledContent("Sets Completed") {
                        Text("\(viewModel.currentSession?.completedSetsCount ?? 0)")
                            .font(.headline)
                    }

                    LabeledContent("Total Volume") {
                        Text(String(format: "%.1f kg", viewModel.currentSession?.totalVolume ?? 0))
                            .font(.headline)
                    }

                    if let percentage = viewModel.currentSession?.completionPercentage {
                        LabeledContent("Completion") {
                            Text("\(percentage)%")
                                .font(.headline)
                                .foregroundStyle(percentage == 100 ? .green : .primary)
                        }
                    }

                    // Estimated calories
                    let estimatedCalories = viewModel.healthKitManager.estimateCaloriesBurned(
                        durationInSeconds: viewModel.currentSession?.duration ?? 0
                    )
                    LabeledContent("Est. Calories") {
                        Text(String(format: "%.0f kcal", estimatedCalories))
                            .font(.headline)
                    }
                } header: {
                    Text("Workout Summary")
                }

                // HealthKit Sync Section
                if viewModel.healthKitManager.isHealthKitAvailable {
                    Section {
                        Toggle(isOn: $syncToHealthKit) {
                            HStack {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(.red)
                                Text("Save to Apple Health")
                            }
                        }
                        .onChange(of: syncToHealthKit) { _, newValue in
                            viewModel.setHealthKitSyncEnabled(newValue)
                        }
                    } footer: {
                        Text("Your workout will appear in the Fitness app and contribute to your activity rings")
                    }
                }

                // Template Update Section
                Section {
                    Toggle("Update Routine Template", isOn: $updateTemplate)
                } footer: {
                    Text("Apply changes to reps and weight back to the routine template for future workouts")
                }

                // Notes Section
                Section {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Workout Notes")
                }
            }
            .navigationTitle("Save Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
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
