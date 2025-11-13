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
    let onComplete: (Exercise, [ExerciseSet]) -> Void

    @State private var sets: [ExerciseSet] = []
    @State private var globalRestTime: TimeInterval = 60.0
    @State private var editingSetIndex: Int?
    @State private var editingReps = 10
    @State private var editingWeight = 0.0

    var body: some View {
        Form {
            Section("Exercise Info") {
                HStack {
                    Text("Name")
                    Spacer()
                    Text(exercise.name)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Muscle Group")
                    Spacer()
                    Text(exercise.muscleGroup)
                        .foregroundColor(.secondary)
                }

                if !exercise.exerciseDescription.isEmpty {
                    HStack(alignment: .top) {
                        Text("Description")
                        Spacer()
                        Text(exercise.exerciseDescription)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            Section("Sets") {
                if sets.isEmpty {
                    // Empty state
                    VStack(spacing: 8) {
                        Text("No sets configured")
                            .foregroundColor(.secondary)
                            .font(.caption)

                        Text("Tap 'Add Set' below to start")
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
                                    Text("Set \(index + 1)")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text("\(set.reps) reps • \(set.weight, specifier: "%.1f") kg")
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
                                        Text("Reps:")
                                        Spacer()
                                        Stepper("\(editingReps)", value: $editingReps, in: 1...100)
                                            .onChange(of: editingReps) { _, _ in
                                                updateSet(at: index)
                                            }
                                    }

                                    HStack {
                                        Text("Weight (kg):")
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
                        Text("Add Set")
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())

                    if !sets.isEmpty {
                        Button(action: duplicateLastSet) {
                            Text("Duplicate Last Set")
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

            Section("Rest Timer") {
                HStack {
                    Text("Rest Time Between Sets")
                    Spacer()
                    Text("\(Int(globalRestTime))s")
                }
                Slider(value: $globalRestTime, in: 0...300, step: 5)
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add to Routine") {
                    addToRoutine()
                }
                .disabled(sets.isEmpty)
            }
        }
        .onAppear {
            // Auto-create first set with defaults
            if sets.isEmpty {
                addNewSet()
            }
        }
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
