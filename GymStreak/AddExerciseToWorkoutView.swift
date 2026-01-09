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
                exercise.muscleGroup.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private func isExerciseAlreadyInWorkout(_ exercise: Exercise) -> Bool {
        guard let session = workoutViewModel.currentSession else { return false }
        return session.workoutExercises.contains(where: { $0.exerciseName == exercise.name })
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
                                Text("Create New Exercise")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("Add a custom exercise to your library")
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
                                // Muscle group icon (subdued)
                                Image(systemName: MuscleGroups.icon(for: exercise.muscleGroup))
                                    .font(.title3)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, height: 40)
                                    .background(Color.secondary.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(exercise.name)
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        Text(exercise.muscleGroup)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                        if !exercise.exerciseDescription.isEmpty {
                                            Text("•")
                                                .foregroundStyle(.tertiary)
                                            Text(exercise.exerciseDescription)
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(1)
                                        }
                                    }
                                }

                                Spacer()

                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.title3)
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color(.secondarySystemGroupedBackground))
                            .accessibilityLabel("\(exercise.name), \(exercise.muscleGroup), already in workout")
                            .accessibilityHint("This exercise is already in your current workout")
                        }
                    } header: {
                        Label("Already in Workout", systemImage: "checkmark.circle.fill")
                    }
                }

                // Section 2: Available Exercises
                let availableExercises = filteredExercises.filter { !isExerciseAlreadyInWorkout($0) }
                if !availableExercises.isEmpty {
                    Section("Available Exercises") {
                        ForEach(availableExercises) { exercise in
                            Button {
                                addExercise(exercise)
                            } label: {
                                HStack(spacing: 12) {
                                    // Muscle group icon (active)
                                    Image(systemName: MuscleGroups.icon(for: exercise.muscleGroup))
                                        .font(.title3)
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(Color.appAccent)
                                        .frame(width: 40, height: 40)
                                        .background(Color.appAccent.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(exercise.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        HStack {
                                            Text(exercise.muscleGroup)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            if !exercise.exerciseDescription.isEmpty {
                                                Text("•")
                                                    .foregroundStyle(.secondary)
                                                Text(exercise.exerciseDescription)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
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
                            .accessibilityLabel("Add \(exercise.name), \(exercise.muscleGroup)")
                            .accessibilityHint("Double-tap to add to workout")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search exercises or muscle groups")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
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
