import SwiftUI

enum ExerciseFormPresentationMode {
    case sheet      // Wrapped in NavigationView, has cancel button
    case navigation // No NavigationView wrapper, uses nav back button
}

struct AddExerciseView: View {
    @ObservedObject var viewModel: ExercisesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var exerciseName = ""
    @State private var muscleGroups: [String] = ["Chest"]
    @State private var equipmentType: EquipmentType = .dumbbell

    var presentationMode: ExerciseFormPresentationMode = .sheet
    var onExerciseCreated: ((Exercise) -> Void)?

    var body: some View {
        Group {
            if presentationMode == .sheet {
                NavigationView {
                    formContent
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("action.cancel".localized) {
                                    dismiss()
                                }
                            }
                            ToolbarItem(placement: .navigationBarTrailing) {
                                saveButton
                            }
                        }
                }
            } else {
                formContent
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            saveButton
                        }
                    }
            }
        }
    }

    private var formContent: some View {
        Form {
            Section {
                TextField("exercises.name".localized, text: $exerciseName)

                MuscleGroupPicker(selectedMuscleGroups: $muscleGroups)

                EquipmentTypePicker(selectedEquipmentType: $equipmentType)
            }
        }
        .navigationTitle("add_exercise.title".localized)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var saveButton: some View {
        Button("action.save".localized) {
            saveExercise()
        }
        .disabled(exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || muscleGroups.isEmpty)
    }

    private func saveExercise() {
        let trimmedName = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let newExercise = viewModel.addExercise(
            name: trimmedName,
            muscleGroups: muscleGroups,
            equipmentType: equipmentType
        )

        if let newExercise = newExercise {
            onExerciseCreated?(newExercise)
        }

        dismiss()
    }
}

#Preview {
    Text("AddExerciseView Preview")
}
