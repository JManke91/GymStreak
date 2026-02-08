import SwiftUI

struct EditExerciseView: View {
    let exercise: Exercise
    @ObservedObject var viewModel: ExercisesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var exerciseName: String
    @State private var muscleGroups: [String]
    @State private var showingDeleteAlert = false

    init(exercise: Exercise, viewModel: ExercisesViewModel) {
        self.exercise = exercise
        self.viewModel = viewModel
        self._exerciseName = State(initialValue: exercise.name)
        self._muscleGroups = State(initialValue: exercise.muscleGroups)
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    TextField("exercises.name".localized, text: $exerciseName)

                    MuscleGroupPicker(selectedMuscleGroups: $muscleGroups)
                }
            }
            .navigationTitle("edit_exercise.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("action.cancel".localized) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("action.save".localized) {
                        saveExercise()
                    }
                    .disabled(exerciseName.isEmpty || muscleGroups.isEmpty)
                }
            }
            .alert("edit_exercise.delete_title".localized, isPresented: $showingDeleteAlert) {
                Button("action.delete".localized, role: .destructive) {
                    viewModel.deleteExercise(exercise)
                    dismiss()
                }
                Button("action.cancel".localized, role: .cancel) {}
            } message: {
                Text("edit_exercise.delete_message".localized(exercise.name))
            }
        }
    }

    private func saveExercise() {
        exercise.name = exerciseName
        exercise.muscleGroups = muscleGroups
        viewModel.updateExercise(exercise)
        dismiss()
    }
}

#Preview {
    Text("EditExerciseView Preview")
}

