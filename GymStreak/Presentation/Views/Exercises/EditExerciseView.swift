import SwiftUI

struct EditExerciseView: View {
    let exercise: Exercise
    @ObservedObject var viewModel: ExercisesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var exerciseName: String
    @State private var muscleGroups: [String]
    @State private var equipmentType: EquipmentType

    init(exercise: Exercise, viewModel: ExercisesViewModel) {
        self.exercise = exercise
        self.viewModel = viewModel
        self._exerciseName = State(initialValue: exercise.name)
        self._muscleGroups = State(initialValue: exercise.muscleGroups)
        self._equipmentType = State(initialValue: exercise.equipmentType)
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    TextField("exercises.name".localized, text: $exerciseName)

                    MuscleGroupPicker(selectedMuscleGroups: $muscleGroups)

                    EquipmentTypePicker(selectedEquipmentType: $equipmentType)
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
            .alert("exercises.delete.confirmation.title".localized, isPresented: $viewModel.showingDeleteConfirmation) {
                Button("common.cancel".localized, role: .cancel) {
                    viewModel.cancelDeleteExercise()
                }
                Button("exercises.delete.confirm".localized, role: .destructive) {
                    viewModel.confirmDeleteExercise()
                    dismiss()
                }
            } message: {
                let exerciseName = viewModel.exerciseToDelete?.name ?? ""
                let routineNames = viewModel.routinesUsingExercise.map(\.name).joined(separator: ", ")
                Text(String(format: "exercises.delete.confirmation.message".localized, exerciseName, routineNames))
            }
            .onChange(of: viewModel.exercises) { _, exercises in
                // Dismiss if the current exercise was deleted
                if !exercises.contains(where: { $0.id == exercise.id }) {
                    dismiss()
                }
            }
        }
    }

    private func saveExercise() {
        exercise.name = exerciseName
        exercise.muscleGroups = muscleGroups
        exercise.equipmentType = equipmentType
        viewModel.updateExercise(exercise)
        dismiss()
    }
}

#Preview {
    Text("EditExerciseView Preview")
}

