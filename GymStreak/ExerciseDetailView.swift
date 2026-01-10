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
            Section("exercise_detail.details".localized) {
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

                HStack {
                    Text("exercises.muscle_group".localized)
                    Spacer()
                    if isEditing {
                        Picker("exercises.muscle_group".localized, selection: $muscleGroup) {
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
                        Text("exercises.description".localized)
                        Spacer()
                        if isEditing {
                            TextField("exercise_detail.optional".localized, text: $exerciseDescription, axis: .vertical)
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

            Section("exercise_detail.info".localized) {
                HStack {
                    Text("exercise_detail.created".localized)
                    Spacer()
                    Text(exercise.createdAt, style: .date)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("exercise_detail.last_updated".localized)
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
                    Button("action.done".localized) {
                        saveExercise()
                    }
                    .disabled(exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Menu {
                        Button("exercise.edit".localized) {
                            enterEditMode()
                        }
                        Button("exercise.delete".localized, role: .destructive) {
                            showingDeleteAlert = true
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
        .alert("exercise_detail.delete_title".localized, isPresented: $showingDeleteAlert) {
            Button("action.delete".localized, role: .destructive) {
                viewModel.deleteExercise(exercise)
            }
            Button("action.cancel".localized, role: .cancel) {}
        } message: {
            Text("exercise_detail.delete_message".localized(exercise.name))
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
