import SwiftUI

struct ExercisePickerView: View {
    @Binding var selectedExercise: Exercise?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dependencies: AppDependencies

    @State private var exercises: [Exercise] = []
    @State private var searchText = ""
    
    var filteredExercises: [Exercise] {
        if searchText.isEmpty {
            return exercises
        } else {
            return exercises.filter { exercise in
                exercise.name.localizedCaseInsensitiveContains(searchText) ||
                exercise.muscleGroups.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(filteredExercises) { exercise in
                    Button(action: {
                        selectedExercise = exercise
                        dismiss()
                    }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            HStack(spacing: 6) {
                                Text(MuscleGroups.displayString(for: exercise.muscleGroups))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Image(systemName: exercise.equipmentType.icon)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "exercise_picker.search".localized)
            .navigationTitle("exercise_picker.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("action.cancel".localized) {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            fetchExercises()
        }
    }
    
    private func fetchExercises() {
        exercises = dependencies.exerciseRepository.fetchAll()
    }
}

#Preview {
    Text("ExercisePickerView Preview")
}
