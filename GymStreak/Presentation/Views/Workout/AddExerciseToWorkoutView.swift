import SwiftUI

struct AddExerciseToWorkoutView: View {
    @ObservedObject var workoutViewModel: WorkoutViewModel
    @ObservedObject var exercisesViewModel: ExercisesViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dependencies: AppDependencies

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
                                .foregroundStyle(DesignSystem.Colors.tint)
                                .frame(width: 40, height: 40)
                                .background(DesignSystem.Colors.tint.opacity(0.1))
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
                                    HStack(spacing: 6) {
                                        Text(MuscleGroups.displayString(for: exercise.muscleGroups))
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                        Image(systemName: exercise.equipmentType.icon)
                                            .font(.caption2)
                                            .foregroundStyle(.quaternary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.title3)
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color(.secondarySystemGroupedBackground))
                            .accessibilityLabel("\(exercise.name), \(MuscleGroups.displayString(for: exercise.muscleGroups)), \(exercise.equipmentType.displayName), already in workout")
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
                                navigationPath.append(exercise.id)
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
                                        HStack(spacing: 6) {
                                            Text(MuscleGroups.displayString(for: exercise.muscleGroups))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Image(systemName: exercise.equipmentType.icon)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
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
                            .accessibilityLabel("Add \(exercise.name), \(MuscleGroups.displayString(for: exercise.muscleGroups)), \(exercise.equipmentType.displayName)")
                            .accessibilityHint("add_to_workout.configure_hint".localized)
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
                    AddExerciseView(
                        viewModel: exercisesViewModel,
                        presentationMode: .navigation,
                        onExerciseCreated: { newExercise in
                            navigationPath.removeLast()
                            exercises.append(newExercise)
                            navigationPath.append(newExercise.id)
                        }
                    )
                }
            }
            .navigationDestination(for: UUID.self) { exerciseId in
                if let exercise = exercises.first(where: { $0.id == exerciseId }) {
                    ConfigureExerciseSetsView(
                        exercise: exercise,
                        navigationTitleKey: "add_to_workout.title",
                        saveButtonKey: "add_to_workout.add",
                        includesAlternatives: false,
                        onSave: { exercise, configuredSets, _ in
                            addExercise(exercise, configuredSets: configuredSets)
                        }
                    )
                }
            }
        }
    }

    private func fetchExercises() {
        exercises = dependencies.exerciseRepository.fetchAll()
    }

    private func addExercise(_ exercise: Exercise, configuredSets: [ExerciseSet]) {
        workoutViewModel.addExerciseToWorkout(exercise: exercise, configuredSets: configuredSets)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dismiss()
    }
}
