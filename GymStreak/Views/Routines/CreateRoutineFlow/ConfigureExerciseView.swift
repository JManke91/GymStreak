//
//  ConfigureExerciseView.swift
//  GymStreak
//
//  Created by Claude Code
//

import SwiftUI

struct ConfigureExerciseView: View {
    @Environment(\.dismiss) private var dismiss

    let exercise: Exercise
    let existingSets: [ExerciseSet]?
    let onComplete: (Exercise, [ExerciseSet]) -> Void

    @State private var sets: [ExerciseSet] = []
    @State private var globalRestTime: TimeInterval = 0.0
    @State private var editingSetIndex: Int?
    @State private var editingReps = 10
    @State private var editingWeight = 0.0

    init(exercise: Exercise, existingSets: [ExerciseSet]? = nil, onComplete: @escaping (Exercise, [ExerciseSet]) -> Void) {
        self.exercise = exercise
        self.existingSets = existingSets
        self.onComplete = onComplete
    }

    var body: some View {
        Form {
            Section("configure_exercise.info".localized) {
                HStack {
                    Text("exercises.name".localized)
                    Spacer()
                    Text(exercise.name)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("exercises.muscle_group".localized)
                    Spacer()
                    Text(exercise.muscleGroup)
                        .foregroundColor(.secondary)
                }

                if !exercise.exerciseDescription.isEmpty {
                    HStack(alignment: .top) {
                        Text("exercises.description".localized)
                        Spacer()
                        Text(exercise.exerciseDescription)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            Section("configure_exercise.sets".localized) {
                if sets.isEmpty {
                    // Empty state
                    VStack(spacing: 8) {
                        Text("configure_exercise.empty.title".localized)
                            .foregroundColor(.secondary)
                            .font(.caption)

                        Text("configure_exercise.empty.description".localized)
                            .foregroundColor(.secondary)
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    ForEach(Array(sets.enumerated()), id: \.offset) { index, set in
                        VStack(alignment: .leading, spacing: 0) {
                            // Display set with tap to edit
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    // Toggle editing
                                    if editingSetIndex == index {
                                        editingSetIndex = nil
                                    } else {
                                        editingSetIndex = index
                                        editingReps = set.reps
                                        editingWeight = set.weight
                                    }
                                }
                            }) {
                                HStack {
                                    Text("set.number".localized(index + 1))
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text("configure_exercise.set_detail".localized(set.reps, set.weight))
                                        .foregroundColor(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .rotationEffect(.degrees(editingSetIndex == index ? 90 : 0))
                                        .animation(.easeInOut(duration: 0.2), value: editingSetIndex == index)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())

                            // Inline edit form for this set
                            if editingSetIndex == index {
                                VStack(spacing: 12) {
                                    HStack {
                                        Text("set.reps_label".localized + ":")
                                        Spacer()
                                        Stepper("\(editingReps)", value: $editingReps, in: 1...100)
                                            .onChange(of: editingReps) { _, _ in
                                                updateSet(at: index)
                                            }
                                    }

                                    HStack {
                                        Text("set.weight_label".localized + ":")
                                        Spacer()
                                        TextField("0.0", value: $editingWeight, format: .number)
                                            .keyboardType(.decimalPad)
                                            .multilineTextAlignment(.trailing)
                                            .frame(width: 80)
                                            .onChange(of: editingWeight) { _, _ in
                                                updateSet(at: index)
                                            }
                                    }
                                }
                                .padding(.top, 8)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                                    removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                                ))
                            }
                        }
                    }
                    .onDelete(perform: deleteSets)
                }

                VStack(spacing: 4) {
                    Button(action: addNewSet) {
                        Text("exercise.add_set".localized)
                            .foregroundColor(Color.appAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.appAccent.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())

                    if !sets.isEmpty {
                        Button(action: duplicateLastSet) {
                            Text("configure_exercise.duplicate_set".localized)
                                .foregroundColor(.green)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }

            Section("configure_exercise.rest_timer".localized) {
                HStack {
                    Text("configure_exercise.rest_time_between_sets".localized)
                    Spacer()
                    Text(TimeFormatting.formatRestTime(globalRestTime))
                }
                Slider(value: $globalRestTime, in: 0...300, step: 30)
                    .onChange(of: globalRestTime) { _, newValue in
                        let rounded = round(newValue / 30) * 30
                        if rounded != globalRestTime {
                            globalRestTime = rounded
                        }
                    }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !isEditMode {
                    Button("configure_exercise.add_to_routine".localized) {
                        addToRoutine()
                    }
                    .disabled(sets.isEmpty)
                }
            }
        }
        .navigationBarBackButtonHidden(false)
        .onDisappear {
            // Auto-save when navigating back in edit mode
            if isEditMode && !sets.isEmpty {
                // Apply global rest time to all sets
                for i in 0..<sets.count {
                    sets[i].restTime = globalRestTime
                }
                // Call completion handler
                onComplete(exercise, sets)
            }
        }
        .onAppear {
            // Load existing sets if in edit mode, otherwise create default set
            if let existingSets = existingSets, !existingSets.isEmpty {
                // Edit mode: copy existing sets (create new instances to avoid modifying originals)
                sets = existingSets.map { ExerciseSet(reps: $0.reps, weight: $0.weight, restTime: $0.restTime) }
                // Set global rest time from first set
                if let firstSet = sets.first {
                    globalRestTime = firstSet.restTime
                }
            } else if sets.isEmpty {
                // New mode: auto-create first set with defaults
                addNewSet()
            }
        }
    }

    // MARK: - Computed Properties

    private var isEditMode: Bool {
        existingSets != nil && !(existingSets?.isEmpty ?? true)
    }

    // MARK: - Helper Methods

    private func addNewSet() {
        let newSet = ExerciseSet(reps: 10, weight: 0.0, restTime: globalRestTime)
        sets.append(newSet)

        // Auto-open the newly added set for editing
        withAnimation(.easeInOut(duration: 0.3)) {
            editingSetIndex = sets.count - 1
            editingReps = newSet.reps
            editingWeight = newSet.weight
        }
    }

    private func duplicateLastSet() {
        guard let lastSet = sets.last else { return }

        let repsToUse: Int
        let weightToUse: Double

        // If the last set is currently being edited, use the editing values
        if let editingIndex = editingSetIndex, editingIndex == sets.count - 1 {
            repsToUse = editingReps
            weightToUse = editingWeight
        } else {
            repsToUse = lastSet.reps
            weightToUse = lastSet.weight
        }

        let newSet = ExerciseSet(reps: repsToUse, weight: weightToUse, restTime: globalRestTime)
        sets.append(newSet)

        // Open the new set for editing
        withAnimation(.easeInOut(duration: 0.3)) {
            editingSetIndex = sets.count - 1
            editingReps = newSet.reps
            editingWeight = newSet.weight
        }
    }

    private func updateSet(at index: Int) {
        guard index < sets.count else { return }
        sets[index].reps = editingReps
        sets[index].weight = editingWeight
    }

    private func deleteSets(offsets: IndexSet) {
        sets.remove(atOffsets: offsets)
        // Reset editing if the edited set was deleted
        if let editingIndex = editingSetIndex, editingIndex >= sets.count {
            editingSetIndex = nil
        }
    }

    private func addToRoutine() {
        // Apply global rest time to all sets
        for i in 0..<sets.count {
            sets[i].restTime = globalRestTime
        }

        // Call completion handler
        onComplete(exercise, sets)

        // Pop back to CreateRoutineView
        dismiss()
    }
}
