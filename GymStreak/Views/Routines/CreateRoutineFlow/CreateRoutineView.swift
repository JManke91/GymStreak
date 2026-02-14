//
//  CreateRoutineView.swift
//  GymStreak
//
//  Created by Claude Code
//

import SwiftUI
import SwiftData

struct CreateRoutineView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var routineName: String = ""
    @State private var pendingExercises: [PendingRoutineExercise] = []
    @State private var showingCancelAlert = false
    @State private var navigateToExerciseSelection = false

    let routinesViewModel: RoutinesViewModel
    let exercisesViewModel: ExercisesViewModel

    var body: some View {
        Form {
            Section {
                TextField("create_routine.name_placeholder".localized, text: $routineName)
                    .font(.title3)
            } header: {
                Text("create_routine.name".localized.uppercased())
            }

            Section {
                if pendingExercises.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        VStack(spacing: 4) {
                            Text("create_routine.empty.title".localized)
                                .font(.headline)

                            Text("create_routine.empty.description".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    // Exercise list
                    ForEach(pendingExercises) { pending in
                        NavigationLink(destination: ConfigureExerciseView(
                            exercise: pending.exercise,
                            existingSets: pending.sets,
                            onComplete: { exercise, sets in
                                updateExercise(pendingExercise: pending, withSets: sets)
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pending.exercise.name)
                                    .font(.headline)

                                Text(pending.setSummary)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteExercise(pending)
                            } label: {
                                Label("action.delete".localized, systemImage: "trash")
                            }
                        }
                    }
                    .onMove { source, destination in
                        pendingExercises.move(fromOffsets: source, toOffset: destination)
                        updateOrder()
                    }
                }

                NavigationLink(destination: ExerciseSelectionView(
                    routinesViewModel: routinesViewModel,
                    exercisesViewModel: exercisesViewModel,
                    alreadyAddedExercises: pendingExercises.map { $0.exercise },
                    onExerciseConfigured: { exercise, sets in
                        addExercise(exercise: exercise, sets: sets)
                    }
                )) {
                    Text("routine.add_exercise".localized)
                }
            } header: {
                Text("exercises.title".localized.uppercased())
            }
        }
        .navigationTitle("create_routine.new_title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("action.cancel".localized) {
                    if hasUnsavedChanges {
                        showingCancelAlert = true
                    } else {
                        dismiss()
                    }
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("action.save".localized) {
                    saveRoutine()
                }
                .disabled(!canSave)
            }
        }
        .alert("create_routine.discard.title".localized, isPresented: $showingCancelAlert) {
            Button("create_routine.keep_editing".localized, role: .cancel) { }
            Button("create_routine.discard".localized, role: .destructive) {
                dismiss()
            }
        } message: {
            Text("create_routine.discard.message".localized)
        }
    }

    // MARK: - Computed Properties

    private var canSave: Bool {
        !routineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasUnsavedChanges: Bool {
        !routineName.isEmpty || !pendingExercises.isEmpty
    }

    // MARK: - Helper Methods

    private func addExercise(exercise: Exercise, sets: [ExerciseSet]) {
        let order = pendingExercises.count
        let pending = PendingRoutineExercise(exercise: exercise, sets: sets, order: order)
        pendingExercises.append(pending)
    }

    private func updateExercise(pendingExercise: PendingRoutineExercise, withSets sets: [ExerciseSet]) {
        if let index = pendingExercises.firstIndex(where: { $0.id == pendingExercise.id }) {
            pendingExercises[index].sets = sets
        }
    }

    private func deleteExercise(_ pending: PendingRoutineExercise) {
        pendingExercises.removeAll { $0.id == pending.id }
        updateOrder()
    }

    private func updateOrder() {
        for (index, _) in pendingExercises.enumerated() {
            pendingExercises[index].order = index
        }
    }

    private func saveRoutine() {
        let trimmedName = routineName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        // Create routine
        let routine = Routine(name: trimmedName)
        modelContext.insert(routine)

        // Create routine exercises and sets
        for pending in pendingExercises {
            let routineExercise = RoutineExercise(
                exercise: pending.exercise,
                order: pending.order
            )
            routineExercise.routine = routine

            // Create sets for this routine exercise
            for (index, set) in pending.sets.enumerated() {
                let newSet = ExerciseSet(
                    reps: set.reps,
                    weight: set.weight,
                    restTime: set.restTime,
                    order: index
                )
                newSet.routineExercise = routineExercise
                routineExercise.sets?.append(newSet)
                modelContext.insert(newSet)
            }

            routine.routineExercises?.append(routineExercise)
            modelContext.insert(routineExercise)
        }

        // Save context
        do {
            try modelContext.save()
            routinesViewModel.updateModelContext(modelContext)
            dismiss()
        } catch {
            print("Error saving routine: \(error)")
        }
    }
}
