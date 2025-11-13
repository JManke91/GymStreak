import SwiftUI

struct EditExerciseView: View {
    let exercise: Exercise
    @ObservedObject var viewModel: ExercisesViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var exerciseName: String
    @State private var muscleGroup: String
    @State private var exerciseDescription: String
    @State private var showingDeleteAlert = false
    
    private let muscleGroups = ["General", "Arms", "Legs", "Chest", "Back", "Shoulders", "Core", "Glutes", "Calves", "Full Body"]
    
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
                Section("Exercise Details") {
                    TextField("Exercise Name", text: $exerciseName)
                    
                    Picker("Muscle Group", selection: $muscleGroup) {
                        ForEach(muscleGroups, id: \.self) { muscleGroup in
                            Text(muscleGroup).tag(muscleGroup)
                        }
                    }
                    
                    TextField("Description (Optional)", text: $exerciseDescription, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveExercise()
                    }
                    .disabled(exerciseName.isEmpty)
                }
            }
            .alert("Delete Exercise", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    viewModel.deleteExercise(exercise)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete '\(exercise.name)'? This action cannot be undone.")
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

