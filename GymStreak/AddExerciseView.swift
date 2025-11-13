import SwiftUI

struct AddExerciseView: View {
    @ObservedObject var viewModel: ExercisesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var exerciseName = ""
    @State private var muscleGroup = "General"
    @State private var exerciseDescription = ""

    private let muscleGroups = ["General", "Arms", "Legs", "Chest", "Back", "Shoulders", "Core", "Glutes", "Calves", "Full Body"]

    // Optional callback when exercise is created (for use in CreateRoutineFlow)
    var onExerciseCreated: ((Exercise) -> Void)?
    
    var body: some View {
        NavigationView {
            Form {
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
            .navigationTitle("New Exercise")
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
