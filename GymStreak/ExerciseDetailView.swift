import SwiftUI

struct ExerciseDetailView: View {
    let exercise: Exercise
    @ObservedObject var viewModel: ExercisesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false

    @State private var exerciseName: String = ""
    @State private var muscleGroups: [String] = []
    @State private var equipmentType: EquipmentType = .dumbbell

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

                if isEditing {
                    EquipmentTypePicker(selectedEquipmentType: $equipmentType)
                } else {
                    HStack {
                        Text("exercises.equipment_type".localized)
                        Spacer()
                        Label(exercise.equipmentType.displayName, systemImage: exercise.equipmentType.icon)
                            .foregroundColor(.secondary)
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
                            viewModel.requestDeleteExercise(exercise)
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
        .onAppear {
            loadExerciseData()
        }
        .onChange(of: viewModel.exercises) { _, exercises in
            // Dismiss if the current exercise was deleted
            if !exercises.contains(where: { $0.id == exercise.id }) {
                dismiss()
            }
        }
    }

    private func loadExerciseData() {
        exerciseName = exercise.name
        muscleGroups = exercise.muscleGroups
        equipmentType = exercise.equipmentType
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
            exercise.equipmentType = equipmentType
            viewModel.updateExercise(exercise)
            isEditing = false
        }
    }
}

#Preview {
    Text("ExerciseDetailView Preview")
}
