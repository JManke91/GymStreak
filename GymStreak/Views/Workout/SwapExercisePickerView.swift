import SwiftUI

/// Compact sheet for swapping a live-workout exercise to one of its
/// pre-configured alternatives (or back to the originally-planned exercise).
/// Rows show each target's own set scheme so the choice is informed.
struct SwapExercisePickerView: View {
    let workoutExercise: WorkoutExercise
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Current exercise, for orientation (not selectable)
                Section {
                    HStack {
                        Text(workoutExercise.exerciseName)
                            .fontWeight(.medium)
                        Spacer()
                        Text("workout.swap.current".localized)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(viewModel.swapTargets(for: workoutExercise)) { target in
                        Button {
                            viewModel.swapExercise(workoutExercise, to: target)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            dismiss()
                        } label: {
                            targetRow(for: target)
                        }
                    }
                }
            }
            .navigationTitle("workout.swap.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel".localized) { dismiss() }
                }
            }
        }
        .presentationDetents([.height(320), .large])
        .presentationDragIndicator(.visible)
    }

    private func targetRow(for target: WorkoutViewModel.SwapTarget) -> some View {
        HStack(spacing: 12) {
            Image(systemName: target.isOriginal ? "arrow.uturn.backward" : "arrow.triangle.2.circlepath")
                .font(.body)
                .foregroundStyle(DesignSystem.Colors.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(target.isOriginal
                     ? "workout.swap.revert".localized(target.exercise.name)
                     : target.exercise.name)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Text(subtitle(for: target))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func subtitle(for target: WorkoutViewModel.SwapTarget) -> String {
        var parts = [target.exercise.muscleGroupsDisplay]
        if let scheme = target.setScheme {
            parts.append(scheme)
        }
        return parts.joined(separator: " · ")
    }
}
