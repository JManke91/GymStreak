import SwiftUI

struct EditExerciseView: View {
    let exercise: Exercise
    @ObservedObject var viewModel: ExercisesViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var exerciseName: String
    @State private var muscleGroup: String
    @State private var exerciseDescription: String
    @State private var showingDeleteAlert = false
    
    init(exercise: Exercise, viewModel: ExercisesViewModel) {
        self.exercise = exercise
        self.viewModel = viewModel
        self._exerciseName = State(initialValue: exercise.name)
        self._muscleGroup = State(initialValue: exercise.muscleGroup)
        self._exerciseDescription = State(initialValue: exercise.exerciseDescription)
    }
    
    var body: some View {
        NavigationView {
            List {
                Section("edit_exercise.details".localized) {
                    TextField("exercises.name".localized, text: $exerciseName)

                    Picker("exercises.muscle_group".localized, selection: $muscleGroup) {
                        ForEach(MuscleGroups.all, id: \.self) { muscleGroup in
                            Text(muscleGroup).tag(muscleGroup)
                        }
                    }

                    TextField("edit_exercise.description_optional".localized, text: $exerciseDescription, axis: .vertical)
                        .lineLimit(3...6)
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
                    .disabled(exerciseName.isEmpty)
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
        exercise.muscleGroup = muscleGroup
        exercise.exerciseDescription = exerciseDescription
        viewModel.updateExercise(exercise)
        dismiss()
    }
}

#Preview {
    Text("EditExerciseView Preview")
}

