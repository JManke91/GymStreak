//
//  CreateRoutineView.swift
//  GymStreak
//
//  Created by Claude Code
//

import SwiftUI

struct CreateRoutineView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var routineName: String = ""
    @State private var pendingExercises: [PendingRoutineExercise] = []
    @State private var showingCancelAlert = false
    @State private var showingExercisePicker = false

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
                            existingAlternatives: pending.alternatives,
                            onComplete: { exercise, sets, alternatives in
                                updateExercise(pendingExercise: pending, withSets: sets, alternatives: alternatives)
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

                Button {
                    showingExercisePicker = true
                } label: {
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
        .sheet(isPresented: $showingExercisePicker) {
            RoutineExercisePickerView(
                alreadyAddedExercises: pendingExercises.map { $0.exercise },
                exercisesViewModel: exercisesViewModel,
                routineName: trimmedRoutineName.isEmpty ? nil : trimmedRoutineName,
                onExerciseConfigured: { exercise, sets, alternatives, repMin, repMax in
                    addExercise(
                        exercise: exercise,
                        sets: sets,
                        alternatives: alternatives,
                        targetRepMin: repMin,
                        targetRepMax: repMax
                    )
                }
            )
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

    private var trimmedRoutineName: String {
        routineName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedRoutineName.isEmpty
    }

    private var hasUnsavedChanges: Bool {
        !routineName.isEmpty || !pendingExercises.isEmpty
    }

    // MARK: - Helper Methods

    private func addExercise(
        exercise: Exercise,
        sets: [ExerciseSet],
        alternatives: [PendingAlternative],
        targetRepMin: Int?,
        targetRepMax: Int?
    ) {
        let order = pendingExercises.count
        let pending = PendingRoutineExercise(
            exercise: exercise,
            sets: sets,
            order: order,
            alternatives: alternatives,
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax
        )
        pendingExercises.append(pending)
    }

    private func updateExercise(pendingExercise: PendingRoutineExercise, withSets sets: [ExerciseSet], alternatives: [PendingAlternative]) {
        if let index = pendingExercises.firstIndex(where: { $0.id == pendingExercise.id }) {
            pendingExercises[index].sets = sets
            pendingExercises[index].alternatives = alternatives
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
        routinesViewModel.createRoutine(name: routineName, pendingExercises: pendingExercises)
        dismiss()
    }
}
