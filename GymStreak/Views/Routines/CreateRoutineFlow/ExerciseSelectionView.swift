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
    let onExerciseConfigured: (Exercise, [ExerciseSet]) -> Void

    var body: some View {
        List {
            // Existing exercises
            Section {
                ForEach(filteredExercises) { exercise in
                    NavigationLink(destination: ConfigureExerciseView(
                        exercise: exercise,
                        onComplete: { exercise, sets in
                            onExerciseConfigured(exercise, sets)
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name)
                                .font(.headline)

                            Text(exercise.muscleGroup)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            // Create new exercise option
            Section {
                NavigationLink(destination: AddExerciseView(
                    viewModel: exercisesViewModel,
                    onExerciseCreated: { newExercise in
                        // After creating the exercise, navigate to configure it
                        selectedExercise = newExercise
                        navigateToConfigureExercise = true
                    }
                )) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)

                        Text("Create New Exercise")
                            .foregroundColor(.accentColor)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Select Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search exercises")
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
                exercise.muscleGroup.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
}
