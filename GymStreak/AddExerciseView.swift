import SwiftUI

struct AddExerciseView: View {
    @ObservedObject var viewModel: ExercisesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var exerciseName = ""
    @State private var muscleGroups: [String] = ["Chest"]

    // Optional callback when exercise is created (for use in CreateRoutineFlow)
    var onExerciseCreated: ((Exercise) -> Void)?

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("exercises.name".localized, text: $exerciseName)

                    MuscleGroupPicker(selectedMuscleGroups: $muscleGroups)
                }
            }
            .navigationTitle("add_exercise.title".localized)
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
        }
    }

    private func saveExercise() {
        let newExercise = viewModel.addExercise(name: exerciseName, muscleGroups: muscleGroups)

        // Call completion callback if provided (for CreateRoutineFlow integration)
        if let newExercise = newExercise {
            onExerciseCreated?(newExercise)
        }

        dismiss()
    }
}

#Preview {
    Text("AddExerciseView Preview")
}
