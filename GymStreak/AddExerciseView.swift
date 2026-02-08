import SwiftUI

struct AddExerciseView: View {
    @ObservedObject var viewModel: ExercisesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var exerciseName = ""
    @State private var muscleGroups: [String] = ["Chest"]
    @State private var equipmentType: EquipmentType = .dumbbell

    // Optional callback when exercise is created (for use in CreateRoutineFlow)
    var onExerciseCreated: ((Exercise) -> Void)?

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("exercises.name".localized, text: $exerciseName)

                    MuscleGroupPicker(selectedMuscleGroups: $muscleGroups)

                    EquipmentTypePicker(selectedEquipmentType: $equipmentType)
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
        let newExercise = viewModel.addExercise(name: exerciseName, muscleGroups: muscleGroups, equipmentType: equipmentType)

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
