import SwiftUI

struct RoutineExerciseDetailView: View {
    let routineExercise: RoutineExercise
    @ObservedObject var viewModel: RoutinesViewModel
    @State private var showingEditExercise = false
    @State private var showingDeleteAlert = false
    @State private var editingSetId: UUID?
    @State private var editingReps: Int = 10
    @State private var editingWeight: Double = 0.0
    @State private var globalRestTime: TimeInterval = 60.0
    
    var body: some View {
        List {
            Section("Exercise Info") {
                if let exercise = routineExercise.exercise {
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
                        HStack {
                            Text("Description")
                            Spacer()
                            Text(exercise.exerciseDescription)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } else {
                    Text("Exercise not found")
                        .foregroundColor(.red)
                }
                
                HStack {
                    Text("Sets")
                    Spacer()
                    Text("\(routineExercise.sets.count)")
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Sets") {
                ForEach(Array(routineExercise.sets.enumerated()), id: \.element.id) { index, set in
                    VStack(alignment: .leading, spacing: 0) {
                        // Collapsible set header
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                if editingSetId == set.id {
                                    // Collapse
                                    editingSetId = nil
                                } else {
                                    // Expand and load values
                                    editingSetId = set.id
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
                                    .rotationEffect(.degrees(editingSetId == set.id ? 90 : 0))
                                    .animation(.easeInOut(duration: 0.2), value: editingSetId == set.id)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())

                        // Inline edit form (expanded)
                        if editingSetId == set.id {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Reps:")
                                    Spacer()
                                    Stepper("\(editingReps)", value: $editingReps, in: 1...100)
                                        .onChange(of: editingReps) { _, newValue in
                                            updateSet(set, reps: newValue)
                                        }
                                }

                                HStack {
                                    Text("Weight (kg):")
                                    Spacer()
                                    TextField("0.0", value: $editingWeight, format: .number)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .frame(width: 80)
                                        .onChange(of: editingWeight) { _, newValue in
                                            updateSet(set, weight: newValue)
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

                Button("Add Set") {
                    addNewSet()
                }
                .foregroundColor(.blue)
            }

            Section("Rest Timer") {
                HStack {
                    Text("Rest Time Between Sets")
                    Spacer()
                    Text(TimeFormatting.formatRestTime(globalRestTime))
                }
                Slider(value: $globalRestTime, in: 0...300, step: 30)
                    .onChange(of: globalRestTime) { _, newValue in
                        let rounded = round(newValue / 30) * 30
                        if rounded != globalRestTime {
                            globalRestTime = rounded
                        }
                        updateAllSetsRestTime(rounded)
                    }
            }
        }
        .navigationTitle(routineExercise.exercise?.name ?? "Exercise")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Delete", role: .destructive) {
                    showingDeleteAlert = true
                }
            }
        }
        .alert("Delete Exercise", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let routine = routineExercise.routine {
                    viewModel.removeRoutineExercise(routineExercise, from: routine)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this exercise from the routine? This action cannot be undone.")
        }
        .onAppear {
            // Initialize global rest time from first set, or use default
            if let firstSet = routineExercise.sets.first {
                globalRestTime = firstSet.restTime
            }
        }
    }

    private func deleteSets(offsets: IndexSet) {
        for index in offsets {
            viewModel.removeSet(routineExercise.sets[index], from: routineExercise)
        }
    }

    private func addNewSet() {
        viewModel.addSet(to: routineExercise)

        // Get the newly added set (last one)
        if let newSet = routineExercise.sets.last {
            // Update its rest time to match global setting
            newSet.restTime = globalRestTime
            viewModel.updateSet(newSet)

            // Auto-expand the new set
            withAnimation(.easeInOut(duration: 0.3)) {
                editingSetId = newSet.id
                editingReps = newSet.reps
                editingWeight = newSet.weight
            }
        }
    }

    private func updateSet(_ set: ExerciseSet, reps: Int? = nil, weight: Double? = nil) {
        if let reps = reps {
            set.reps = reps
        }
        if let weight = weight {
            set.weight = weight
        }
        viewModel.updateSet(set)
    }

    private func updateAllSetsRestTime(_ restTime: TimeInterval) {
        for set in routineExercise.sets {
            set.restTime = restTime
            viewModel.updateSet(set)
        }
    }
}

struct SetRowView: View {
    let set: ExerciseSet
    var showChevron: Bool = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set \(set.id.uuidString.prefix(8))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Text("\(set.reps) reps")
                    Text("•")
                    Text("\(set.weight, specifier: "%.1f") kg")
                    Text("•")
                    Text("\(TimeFormatting.formatRestTime(set.restTime)) rest")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            if set.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    Text("RoutineExerciseDetailView Preview")
}
