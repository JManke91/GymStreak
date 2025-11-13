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
                TextField("Routine Name", text: $routineName)
                    .font(.title3)
            } header: {
                Text("ROUTINE NAME")
            }

            Section {
                if pendingExercises.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        VStack(spacing: 4) {
                            Text("Add Your First Exercise")
                                .font(.headline)

                            Text("Build your routine by adding exercises and configuring sets")
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pending.exercise.name)
                                .font(.headline)

                            Text(pending.setSummary)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteExercise(pending)
                            } label: {
                                Label("Delete", systemImage: "trash")
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
                    onExerciseConfigured: { exercise, sets in
                        addExercise(exercise: exercise, sets: sets)
                    }
                )) {
                    HStack {
                        Text("Add Exercise")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("EXERCISES")
            }
        }
        .navigationTitle("New Routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if hasUnsavedChanges {
                        showingCancelAlert = true
                    } else {
                        dismiss()
                    }
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveRoutine()
                }
                .disabled(!canSave)
            }
        }
        .alert("Discard Routine?", isPresented: $showingCancelAlert) {
            Button("Keep Editing", role: .cancel) { }
            Button("Discard", role: .destructive) {
                dismiss()
            }
        } message: {
            Text("You have unsaved changes. Are you sure you want to discard this routine?")
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
            for set in pending.sets {
                let newSet = ExerciseSet(
                    reps: set.reps,
                    weight: set.weight,
                    restTime: set.restTime
                )
                newSet.routineExercise = routineExercise
                routineExercise.sets.append(newSet)
                modelContext.insert(newSet)
            }

            routine.routineExercises.append(routineExercise)
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
