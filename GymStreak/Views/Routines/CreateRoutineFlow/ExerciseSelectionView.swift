//
//  ExerciseSelectionView.swift
//  GymStreak
//
//  Created by Claude Code
//

import SwiftUI
import SwiftData

struct ExerciseSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]

    @State private var searchText = ""
    @State private var navigateToNewExercise = false
    @State private var selectedExercise: Exercise?
    @State private var navigateToConfigureExercise = false

    let routinesViewModel: RoutinesViewModel
    let exercisesViewModel: ExercisesViewModel
    let alreadyAddedExercises: [Exercise]
    let onExerciseConfigured: (Exercise, [ExerciseSet]) -> Void

    var body: some View {
        List {
            // Info section showing count of added exercises
            if !alreadyAddedExercises.isEmpty {
                Section {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(DesignSystem.Colors.tint)
                        Text("exercise_selection.already_added".localized(alreadyAddedExercises.count))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .listRowBackground(DesignSystem.Colors.tint.opacity(0.1))
                }
            }

            // Existing exercises
            Section {
                ForEach(filteredExercises) { exercise in
                    NavigationLink(destination: ConfigureExerciseView(
                        exercise: exercise,
                        onComplete: { exercise, sets in
                            onExerciseConfigured(exercise, sets)
                        }
                    )) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.name)
                                    .font(.headline)

                                Text(MuscleGroups.displayString(for: exercise.muscleGroups))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            // Show checkmark if exercise is already added
                            if isExerciseAlreadyAdded(exercise) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 20))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            // Create new exercise option
            Section {
                NavigationLink(destination: AddExerciseView(
                    viewModel: exercisesViewModel,
                    presentationMode: .navigation,
                    onExerciseCreated: { newExercise in
                        // After creating the exercise, navigate to configure it
                        selectedExercise = newExercise
                        navigateToConfigureExercise = true
                    }
                )) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)

                        Text("exercise_selection.create_new".localized)
                            .foregroundColor(.accentColor)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("exercise_selection.title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "exercise_selection.search".localized)
        .navigationDestination(isPresented: $navigateToConfigureExercise) {
            if let exercise = selectedExercise {
                ConfigureExerciseView(
                    exercise: exercise,
                    onComplete: { exercise, sets in
                        onExerciseConfigured(exercise, sets)
                    }
                )
            }
        }
    }

    // MARK: - Computed Properties

    private var filteredExercises: [Exercise] {
        if searchText.isEmpty {
            return allExercises
        } else {
            return allExercises.filter { exercise in
                exercise.name.localizedCaseInsensitiveContains(searchText) ||
                exercise.muscleGroups.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
    }

    // MARK: - Helper Methods

    private func isExerciseAlreadyAdded(_ exercise: Exercise) -> Bool {
        alreadyAddedExercises.contains(where: { $0.id == exercise.id })
    }
}
