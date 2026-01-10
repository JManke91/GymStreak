import SwiftUI

struct AddExerciseView: View {
    @ObservedObject var viewModel: ExercisesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var exerciseName = ""
    @State private var muscleGroup = "General"
    @State private var exerciseDescription = ""

    // Optional callback when exercise is created (for use in CreateRoutineFlow)
    var onExerciseCreated: ((Exercise) -> Void)?
    
    var body: some View {
        NavigationView {
            Form {
                Section("add_exercise.details".localized) {
                    TextField("exercises.name".localized, text: $exerciseName)

                    Picker("exercises.muscle_group".localized, selection: $muscleGroup) {
                        ForEach(MuscleGroups.all, id: \.self) { muscleGroup in
                            Text(muscleGroup).tag(muscleGroup)
                        }
                    }

                    TextField("add_exercise.description_optional".localized, text: $exerciseDescription, axis: .vertical)
                        .lineLimit(3...6)
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
                    .disabled(exerciseName.isEmpty)
                }
            }
        }
    }
    
    private func saveExercise() {
        let newExercise = viewModel.addExercise(name: exerciseName, muscleGroup: muscleGroup, exerciseDescription: exerciseDescription)

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
