import SwiftUI
import SwiftData

struct AddExerciseToWorkoutView: View {
    @ObservedObject var workoutViewModel: WorkoutViewModel
    @ObservedObject var exercisesViewModel: ExercisesViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var exercises: [Exercise] = []
    @State private var searchText = ""
    @State private var navigationPath = NavigationPath()

    var filteredExercises: [Exercise] {
        if searchText.isEmpty {
            return exercises
        } else {
            return exercises.filter { exercise in
                exercise.name.localizedCaseInsensitiveContains(searchText) ||
                exercise.muscleGroups.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
    }

    private func isExerciseAlreadyInWorkout(_ exercise: Exercise) -> Bool {
        guard let session = workoutViewModel.currentSession else { return false }
        return session.workoutExercisesList.contains(where: { $0.exerciseName == exercise.name })
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                // Section: Create New Exercise
                Section {
                    NavigationLink(value: "createNewExercise") {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.appAccent)
                                .frame(width: 40, height: 40)
                                .background(Color.appAccent.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 4) {
                                Text("add_to_workout.create_new".localized)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("add_to_workout.create_description".localized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .accessibilityLabel("Create new exercise")
                    .accessibilityHint("Opens form to create a custom exercise")
                }

                // Section 1: Already in Workout
                let alreadyAddedExercises = filteredExercises.filter { isExerciseAlreadyInWorkout($0) }
                if !alreadyAddedExercises.isEmpty {
                    Section {
                        ForEach(alreadyAddedExercises) { exercise in
                            HStack(spacing: 12) {
                                // Muscle group badge (subdued)
                                MuscleGroupAbbreviationBadge(
                                    muscleGroups: exercise.muscleGroups,
                                    isActive: false
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(exercise.name)
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                    Text(MuscleGroups.displayString(for: exercise.muscleGroups))
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }

                                Spacer()

                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.title3)
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color(.secondarySystemGroupedBackground))
                            .accessibilityLabel("\(exercise.name), \(MuscleGroups.displayString(for: exercise.muscleGroups)), already in workout")
                            .accessibilityHint("This exercise is already in your current workout")
                        }
                    } header: {
                        Label("add_to_workout.already_added".localized, systemImage: "checkmark.circle.fill")
                    }
                }

                // Section 2: Available Exercises
                let availableExercises = filteredExercises.filter { !isExerciseAlreadyInWorkout($0) }
                if !availableExercises.isEmpty {
                    Section("add_to_workout.available".localized) {
                        ForEach(availableExercises) { exercise in
                            Button {
                                addExercise(exercise)
                            } label: {
                                HStack(spacing: 12) {
                                    // Muscle group badge (active)
                                    MuscleGroupAbbreviationBadge(
                                        muscleGroups: exercise.muscleGroups,
                                        isActive: true
                                    )

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(exercise.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text(MuscleGroups.displayString(for: exercise.muscleGroups))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.title3)
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add \(exercise.name), \(MuscleGroups.displayString(for: exercise.muscleGroups))")
                            .accessibilityHint("Double-tap to add to workout")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("add_to_workout.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "add_to_workout.search".localized)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("action.cancel".localized) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                fetchExercises()
            }
            .navigationDestination(for: String.self) { destination in
                if destination == "createNewExercise" {
                    CreateExerciseInlineView(
                        exercisesViewModel: exercisesViewModel,
                        onExerciseCreated: { newExercise in
                            // Add the newly created exercise to the workout
                            addExercise(newExercise)
                        }
                    )
                }
            }
        }
    }

    private func fetchExercises() {
        let descriptor = FetchDescriptor<Exercise>(
            sortBy: [SortDescriptor(\.name)]
        )
        do {
            exercises = try modelContext.fetch(descriptor)
        } catch {
            print("Failed to fetch exercises: \(error)")
        }
    }

    private func addExercise(_ exercise: Exercise) {
        workoutViewModel.addExerciseToWorkout(exercise: exercise)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dismiss()
    }
}
