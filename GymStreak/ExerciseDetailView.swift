import SwiftUI

struct ExerciseDetailView: View {
    let exercise: Exercise
    @ObservedObject var viewModel: ExercisesViewModel
    @State private var showingDeleteAlert = false
    @State private var isEditing = false

    @State private var exerciseName: String = ""
    @State private var muscleGroup: String = ""
    @State private var exerciseDescription: String = ""

    var body: some View {
        List {
            Section("Exercise Details") {
                HStack {
                    Text("Name")
                    Spacer()
                    if isEditing {
                        TextField("Exercise Name", text: $exerciseName)
                            .multilineTextAlignment(.trailing)
                    } else {
                        Text(exercise.name)
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text("Muscle Group")
                    Spacer()
                    if isEditing {
                        Picker("Muscle Group", selection: $muscleGroup) {
                            ForEach(MuscleGroups.all, id: \.self) { muscleGroup in
                                Text(muscleGroup).tag(muscleGroup)
                            }
                        }
                        .labelsHidden()
                    } else {
                        Text(exercise.muscleGroup)
                            .foregroundColor(.secondary)
                    }
                }

                if isEditing || !exercise.exerciseDescription.isEmpty {
                    HStack(alignment: .top) {
                        Text("Description")
                        Spacer()
                        if isEditing {
                            TextField("Optional", text: $exerciseDescription, axis: .vertical)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(3...6)
                        } else {
                            Text(exercise.exerciseDescription)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }

            Section("Info") {
                HStack {
                    Text("Created")
                    Spacer()
                    Text(exercise.createdAt, style: .date)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Last Updated")
                    Spacer()
                    Text(exercise.updatedAt, style: .date)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isEditing {
                    Button("Done") {
                        saveExercise()
                    }
                    .disabled(exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Menu {
                        Button("Edit Exercise") {
                            enterEditMode()
                        }
                        Button("Delete Exercise", role: .destructive) {
                            showingDeleteAlert = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }

            if isEditing {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        cancelEditing()
                    }
                }
            }
        }
        .alert("Delete Exercise", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                viewModel.deleteExercise(exercise)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete '\(exercise.name)'? This action cannot be undone.")
        }
        .onAppear {
            loadExerciseData()
        }
    }

    private func loadExerciseData() {
        exerciseName = exercise.name
        muscleGroup = exercise.muscleGroup
        exerciseDescription = exercise.exerciseDescription
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
            exercise.muscleGroup = muscleGroup
            exercise.exerciseDescription = exerciseDescription
            viewModel.updateExercise(exercise)
            isEditing = false
        }
    }
}

#Preview {
    Text("ExerciseDetailView Preview")
}
