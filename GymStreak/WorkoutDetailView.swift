import SwiftUI

struct WorkoutDetailView: View {
    let workout: WorkoutSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                // Summary Section
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Date")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(workout.startTime, format: .dateTime.month().day().year())
                                .font(.headline)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Time")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(workout.startTime, format: .dateTime.hour().minute())
                                .font(.headline)
                        }
                    }

                    LabeledContent("Duration") {
                        Text(formatDuration(workout.duration))
                            .font(.headline)
                    }

                    LabeledContent("Sets Completed") {
                        Text("\(workout.completedSetsCount) of \(workout.totalSetsCount)")
                            .font(.headline)
                    }

                    LabeledContent("Completion") {
                        HStack(spacing: 4) {
                            Text("\(workout.completionPercentage)%")
                                .font(.headline)
                            if workout.completionPercentage == 100 {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }

                    LabeledContent("Total Volume") {
                        Text(String(format: "%.1f kg", workout.totalVolume))
                            .font(.headline)
                    }

                    if workout.didUpdateTemplate {
                        Label("Routine template updated", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                } header: {
                    Text("Workout Summary")
                }

                // Notes Section
                if !workout.notes.isEmpty {
                    Section {
                        Text(workout.notes)
                            .font(.body)
                    } header: {
                        Text("Notes")
                    }
                }

                // Exercises Section
                Section {
                    ForEach(workout.workoutExercises.sorted(by: { $0.order < $1.order }), id: \.id) { workoutExercise in
                        WorkoutExerciseDetailCard(workoutExercise: workoutExercise)
                    }
                } header: {
                    Text("Exercises")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(workout.routineName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

// MARK: - Workout Exercise Detail Card

struct WorkoutExerciseDetailCard: View {
    let workoutExercise: WorkoutExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Exercise Header
            HStack {
                Image(systemName: muscleGroupIcon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.appAccent)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(workoutExercise.exerciseName)
                        .font(.headline)

                    Text("\(workoutExercise.completedSetsCount) of \(workoutExercise.sets.count) sets completed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if workoutExercise.completedSetsCount == workoutExercise.sets.count {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                }
            }

            // Sets Table
            VStack(spacing: 8) {
                // Header Row
                HStack {
                    Text("Set")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .leading)

                    Text("Planned")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Actual")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()
                        .frame(width: 24)
                }
                .padding(.horizontal, 8)

                Divider()

                // Set Rows
                ForEach(workoutExercise.sets.sorted(by: { $0.order < $1.order }), id: \.id) { set in
                    HStack {
                        Text("\(set.order + 1)")
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                            .frame(width: 40, alignment: .leading)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(set.plannedReps) reps")
                                .font(.caption)
                            Text(String(format: "%.1f kg", set.plannedWeight))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if set.isCompleted {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text("\(set.actualReps) reps")
                                        .font(.caption)
                                    if set.actualReps > set.plannedReps {
                                        Image(systemName: "arrow.up")
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                    } else if set.actualReps < set.plannedReps {
                                        Image(systemName: "arrow.down")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                }

                                HStack(spacing: 4) {
                                    Text(String(format: "%.1f kg", set.actualWeight))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    if set.actualWeight > set.plannedWeight {
                                        Image(systemName: "arrow.up")
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                    } else if set.actualWeight < set.plannedWeight {
                                        Image(systemName: "arrow.down")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.body)
                                .frame(width: 24)
                        } else {
                            Text("Skipped")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                                .font(.body)
                                .frame(width: 24)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(set.isCompleted ? Color.green.opacity(0.05) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.vertical, 4)
    }

    private var muscleGroupIcon: String {
        MuscleGroups.icon(for: workoutExercise.muscleGroup)
    }
}
