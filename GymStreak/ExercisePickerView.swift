import SwiftUI
import SwiftData

struct ExercisePickerView: View {
    @Binding var selectedExercise: Exercise?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var exercises: [Exercise] = []
    @State private var searchText = ""
    
    var filteredExercises: [Exercise] {
        if searchText.isEmpty {
            return exercises
        } else {
            return exercises.filter { exercise in
                exercise.name.localizedCaseInsensitiveContains(searchText) ||
                exercise.muscleGroup.localizedCaseInsensitiveContains(searchText)
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
                            HStack {
                                Text(exercise.muscleGroup)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if !exercise.exerciseDescription.isEmpty {
                                    Text("•")
                                        .foregroundColor(.secondary)
                                    Text(exercise.exerciseDescription)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
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
        let descriptor = FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name, order: .forward)])
        do {
            exercises = try modelContext.fetch(descriptor)
        } catch {
            print("Error fetching exercises: \(error)")
        }
    }
}

#Preview {
    Text("ExercisePickerView Preview")
}
