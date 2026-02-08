import SwiftUI

struct ExerciseDetailView: View {
    let exercise: Exercise
    @ObservedObject var viewModel: ExercisesViewModel
    @State private var showingDeleteAlert = false
    @State private var isEditing = false

    @State private var exerciseName: String = ""
    @State private var muscleGroups: [String] = []

    var body: some View {
        List {
            Section {
                HStack {
                    Text("exercises.name".localized)
                    Spacer()
                    if isEditing {
                        TextField("exercises.name".localized, text: $exerciseName)
                            .multilineTextAlignment(.trailing)
                    } else {
                        Text(exercise.name)
                            .foregroundColor(.secondary)
                    }
                }

                if isEditing {
                    MuscleGroupPicker(selectedMuscleGroups: $muscleGroups)
                } else {
                    HStack {
                        Text("exercises.muscle_groups".localized)
                        Spacer()
                        Text(MuscleGroups.displayString(for: exercise.muscleGroups))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isEditing {
                    Button("action.done".localized) {
                        saveExercise()
                    }
                    .disabled(exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || muscleGroups.isEmpty)
                } else {
                    Menu {
                        Button("exercise.edit".localized) {
                            enterEditMode()
                        }
                        Button("exercise.delete".localized, role: .destructive) {
                            showingDeleteAlert = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }

            if isEditing {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("action.cancel".localized) {
                        cancelEditing()
                    }
                }
            }
        }
        .alert("exercise_detail.delete_title".localized, isPresented: $showingDeleteAlert) {
            Button("action.delete".localized, role: .destructive) {
                viewModel.deleteExercise(exercise)
            }
            Button("action.cancel".localized, role: .cancel) {}
        } message: {
            Text("exercise_detail.delete_message".localized(exercise.name))
        }
        .onAppear {
            loadExerciseData()
        }
    }

    private func loadExerciseData() {
        exerciseName = exercise.name
        muscleGroups = exercise.muscleGroups
    }

    private func enterEditMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = true
        }
    }

    private func cancelEditing() {
        withAnimation(.easeInOut(duration: 0.2)) {
            loadExerciseData()
            isEditing = false
        }
    }

    private func saveExercise() {
        let trimmedName = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            exercise.name = trimmedName
            exercise.muscleGroups = muscleGroups
            viewModel.updateExercise(exercise)
            isEditing = false
        }
    }
}

#Preview {
    Text("ExerciseDetailView Preview")
}
