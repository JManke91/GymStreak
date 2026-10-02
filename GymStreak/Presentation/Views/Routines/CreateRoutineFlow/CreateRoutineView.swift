//
//  CreateRoutineView.swift
//  GymStreak
//
//  Created by Claude Code
//

import SwiftUI

/// Builds a new routine before it exists. The exercise list deliberately
/// mirrors the routine detail screen — the same cards, superset connector,
/// link/unlink controls and "Sort" mode (see CreateRoutineView+Exercises) — so
/// a routine looks the same while drafting as it does once saved. The draft's
/// edit rules live in `PendingExerciseList`, not here.
struct CreateRoutineView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.weightUnit) var weightUnit

    @State private var routineName: String = ""
    @State var draft = PendingExerciseList()
    @State var editingExerciseId: UUID?
    @State var isSorting = false
    @State var showingExercisePicker = false
    @State private var showingCancelAlert = false

    let routinesViewModel: RoutinesViewModel
    let exercisesViewModel: ExercisesViewModel

    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()

            if isSorting {
                sortingContent
            } else {
                browsingContent
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
                alreadyAddedExercises: draft.exercises.map { $0.exercise },
                exercisesViewModel: exercisesViewModel,
                routineName: trimmedRoutineName.isEmpty ? nil : trimmedRoutineName,
                onExerciseConfigured: { exercise, sets, alternatives, repMin, repMax in
                    draft.append(
                        exercise: exercise,
                        sets: sets,
                        alternatives: alternatives,
                        targetRepMin: repMin,
                        targetRepMax: repMax
                    )
                }
            )
        }
        .navigationDestination(item: $editingExerciseId) { id in
            if let pending = draft.exercise(withId: id) {
                // Same screen as adding an exercise, opened on this
                // draft entry's configuration — see ConfigureExerciseSetsView.
                ConfigureExerciseSetsView(
                    exercise: pending.exercise,
                    navigationTitleKey: "configure_exercise.edit_title",
                    saveButtonKey: "configure_exercise.save_changes",
                    existingConfiguration: .init(
                        sets: pending.sets,
                        alternatives: pending.alternatives,
                        targetRepMin: pending.targetRepMin,
                        targetRepMax: pending.targetRepMax
                    ),
                    onSave: { _, sets, alternatives, repMin, repMax in
                        draft.update(
                            id: id,
                            sets: sets,
                            alternatives: alternatives,
                            targetRepMin: repMin,
                            targetRepMax: repMax
                        )
                    }
                )
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

    // MARK: - Name

    var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            SetsSectionLabel(text: "create_routine.name".localized)

            TextField("create_routine.name_placeholder".localized, text: $routineName)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .routineExerciseCardChassis()
        }
        .padding(.top, 12)
    }

    // MARK: - Computed Properties

    private var trimmedRoutineName: String {
        routineName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedRoutineName.isEmpty
    }

    private var hasUnsavedChanges: Bool {
        !routineName.isEmpty || !draft.isEmpty
    }

    // MARK: - Actions

    private func saveRoutine() {
        routinesViewModel.createRoutine(name: routineName, pendingExercises: draft.exercises)
        dismiss()
    }
}
