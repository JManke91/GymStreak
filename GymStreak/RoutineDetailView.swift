import SwiftUI

struct RoutineDetailView: View {
    let routine: Routine
    @ObservedObject var viewModel: RoutinesViewModel
    @ObservedObject var exercisesViewModel: ExercisesViewModel
    @State private var showingAddExercise = false
    @State private var showingDeleteAlert = false
    @State private var showingEditRoutine = false
    @State private var expandedExerciseId: UUID?
    @State private var expandedSetId: UUID?
    @State private var editingReps: Int = 10
    @State private var editingWeight: Double = 0.0
    @State private var editingRestTime: TimeInterval = 60.0
    
    var body: some View {
        List {
            Section("Routine Info") {
                HStack {
                    Text("Name")
                    Spacer()
                    Text(routine.name)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Exercises")
                    Spacer()
                    Text("\(routine.routineExercises.count)")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Created")
                    Spacer()
                    Text(routine.createdAt, style: .date)
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Exercises") {
                if routine.routineExercises.isEmpty {
                    Text("No exercises added yet")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(routine.routineExercises.sorted(by: { $0.order < $1.order })) { routineExercise in
                        VStack(alignment: .leading, spacing: 0) {
                            // Exercise header (expandable)
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    if expandedExerciseId == routineExercise.id {
                                        expandedExerciseId = nil
                                        expandedSetId = nil
                                    } else {
                                        expandedExerciseId = routineExercise.id
                                        expandedSetId = nil
                                    }
                                }
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        if let exercise = routineExercise.exercise {
                                            Text(exercise.name)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Text("\(routineExercise.sets.count) sets")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .rotationEffect(.degrees(expandedExerciseId == routineExercise.id ? 90 : 0))
                                        .animation(.easeInOut(duration: 0.2), value: expandedExerciseId == routineExercise.id)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.vertical, 4)

                            // Sets list (expanded when exercise is expanded)
                            if expandedExerciseId == routineExercise.id {
                                VStack(spacing: 8) {
                                    ForEach(Array(routineExercise.sets.enumerated()), id: \.element.id) { index, set in
                                        VStack(alignment: .leading, spacing: 0) {
                                            // Set header (expandable)
                                            Button(action: {
                                                withAnimation(.easeInOut(duration: 0.3)) {
                                                    if expandedSetId == set.id {
                                                        expandedSetId = nil
                                                    } else {
                                                        expandedSetId = set.id
                                                        editingReps = set.reps
                                                        editingWeight = set.weight
                                                        editingRestTime = set.restTime
                                                    }
                                                }
                                            }) {
                                                HStack {
                                                    Text("Set \(index + 1)")
                                                        .font(.subheadline)
                                                        .foregroundColor(.primary)
                                                    Spacer()
                                                    Text("\(set.reps) reps • \(set.weight, specifier: "%.1f") kg")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                    Image(systemName: "chevron.right")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                        .rotationEffect(.degrees(expandedSetId == set.id ? 90 : 0))
                                                        .animation(.easeInOut(duration: 0.2), value: expandedSetId == set.id)
                                                }
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            .padding(.leading, 16)

                                            // Set edit form (expanded when set is expanded)
                                            if expandedSetId == set.id {
                                                VStack(spacing: 12) {
                                                    HStack {
                                                        Text("Reps:")
                                                            .font(.caption)
                                                        Spacer()
                                                        Stepper("\(editingReps)", value: $editingReps, in: 1...100)
                                                            .onChange(of: editingReps) { _, newValue in
                                                                updateSet(set, reps: newValue)
                                                            }
                                                    }

                                                    HStack {
                                                        Text("Weight (kg):")
                                                            .font(.caption)
                                                        Spacer()
                                                        TextField("0.0", value: $editingWeight, format: .number)
                                                            .keyboardType(.decimalPad)
                                                            .multilineTextAlignment(.trailing)
                                                            .frame(width: 80)
                                                            .onChange(of: editingWeight) { _, newValue in
                                                                updateSet(set, weight: newValue)
                                                            }
                                                    }

                                                    HStack {
                                                        Text("Rest Time:")
                                                            .font(.caption)
                                                        Spacer()
                                                        Text("\(Int(editingRestTime))s")
                                                            .foregroundColor(.secondary)
                                                            .font(.caption)
                                                    }
                                                    Slider(value: $editingRestTime, in: 0...300, step: 5)
                                                        .onChange(of: editingRestTime) { _, newValue in
                                                            updateSet(set, restTime: newValue)
                                                        }
                                                }
                                                .padding(.leading, 32)
                                                .padding(.top, 8)
                                                .transition(.asymmetric(
                                                    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                                                    removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                                                ))
                                            }
                                        }
                                    }

                                    Button(action: {
                                        viewModel.addSet(to: routineExercise)
                                    }) {
                                        HStack {
                                            Image(systemName: "plus.circle.fill")
                                            Text("Add Set")
                                        }
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    }
                                    .padding(.leading, 16)
                                    .padding(.top, 4)
                                }
                                .padding(.top, 8)
                                .padding(.bottom, 8)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                                    removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                                ))
                            }
                        }
                    }
                    .onDelete(perform: deleteRoutineExercises)
                }

                Button("Add Exercise") {
                    showingAddExercise = true
                }
                .foregroundColor(.blue)
            }
        }
        .navigationTitle(routine.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Edit Routine") {
                        showingEditRoutine = true
                    }
                    Button("Delete Routine", role: .destructive) {
                        showingDeleteAlert = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingAddExercise) {
            AddExerciseToRoutineView(routine: routine, viewModel: viewModel, exercisesViewModel: exercisesViewModel)
        }
        .sheet(isPresented: $showingEditRoutine) {
            EditRoutineNameView(routine: routine, viewModel: viewModel)
        }
        .alert("Delete Routine", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                viewModel.deleteRoutine(routine)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete '\(routine.name)'? This action cannot be undone.")
        }
    }
    
    private func deleteRoutineExercises(offsets: IndexSet) {
        for index in offsets {
            let routineExercise = routine.routineExercises.sorted(by: { $0.order < $1.order })[index]
            viewModel.removeRoutineExercise(routineExercise, from: routine)
        }
    }

    private func updateSet(_ set: ExerciseSet, reps: Int? = nil, weight: Double? = nil, restTime: TimeInterval? = nil) {
        if let reps = reps {
            set.reps = reps
        }
        if let weight = weight {
            set.weight = weight
        }
        if let restTime = restTime {
            set.restTime = restTime
        }
        viewModel.updateSet(set)
    }
}

// Edit Routine Name Sheet
struct EditRoutineNameView: View {
    let routine: Routine
    @ObservedObject var viewModel: RoutinesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var routineName: String

    init(routine: Routine, viewModel: RoutinesViewModel) {
        self.routine = routine
        self.viewModel = viewModel
        self._routineName = State(initialValue: routine.name)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Routine Name") {
                    TextField("Routine Name", text: $routineName)
                }
            }
            .navigationTitle("Edit Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveRoutine()
                    }
                    .disabled(routineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func saveRoutine() {
        let trimmedName = routineName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        routine.name = trimmedName
        routine.updatedAt = Date()
        viewModel.updateRoutine(routine)
        dismiss()
    }
}

#Preview {
    Text("RoutineDetailView Preview")
}
