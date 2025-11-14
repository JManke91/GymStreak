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
            Section {
                InfoRow(label: "Name", value: routine.name)
                InfoRow(label: "Exercises", value: "\(routine.routineExercises.count)")
                InfoRow(label: "Created", value: routine.createdAt.formatted(date: .abbreviated, time: .omitted))
            } header: {
                Text("Routine Info")
            }
            .listRowSeparator(.hidden)

            Section {
                if routine.routineExercises.isEmpty {
                    ContentUnavailableView {
                        Label("No Exercises", systemImage: "dumbbell")
                    } description: {
                        Text("Add exercises to build your workout routine")
                    } actions: {
                        Button("Add Exercise") {
                            showingAddExercise = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(routine.routineExercises.sorted(by: { $0.order < $1.order })) { routineExercise in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedExerciseId == routineExercise.id },
                                set: { isExpanded in
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        if isExpanded {
                                            expandedExerciseId = routineExercise.id
                                            expandedSetId = nil
                                        } else {
                                            expandedExerciseId = nil
                                            expandedSetId = nil
                                        }
                                    }
                                }
                            )
                        ) {
                            // Sets content
                            VStack(spacing: 12) {
                                ForEach(Array(routineExercise.sets.enumerated()), id: \.element.id) { index, set in
                                    RoutineSetRowView(
                                        set: set,
                                        index: index,
                                        isExpanded: expandedSetId == set.id,
                                        editingReps: $editingReps,
                                        editingWeight: $editingWeight,
                                        editingRestTime: $editingRestTime,
                                        onTap: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                if expandedSetId == set.id {
                                                    expandedSetId = nil
                                                } else {
                                                    expandedSetId = set.id
                                                    editingReps = set.reps
                                                    editingWeight = set.weight
                                                    editingRestTime = set.restTime
                                                }
                                            }
                                        },
                                        onUpdate: { reps, weight, restTime in
                                            updateSet(set, reps: reps, weight: weight, restTime: restTime)
                                        }
                                    )
                                }

                                Button {
                                    viewModel.addSet(to: routineExercise)
                                } label: {
                                    Label("Add Set", systemImage: "plus.circle.fill")
                                        .font(.subheadline.weight(.medium))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(.blue)
                            }
                            .padding(.vertical, 8)

                        } label: {
                            ExerciseHeaderView(routineExercise: routineExercise)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .sensoryFeedback(.selection, trigger: expandedExerciseId)
                    }
                    .onDelete(perform: deleteRoutineExercises)
                }

                if !routine.routineExercises.isEmpty {
                    Button {
                        showingAddExercise = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            } header: {
                Text("Exercises")
            }
        }
        .listStyle(.insetGrouped)
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

// MARK: - Supporting Views

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

struct ExerciseHeaderView: View {
    let routineExercise: RoutineExercise

    var body: some View {
        HStack(spacing: 12) {
            // Muscle group icon
            if let exercise = routineExercise.exercise {
                Image(systemName: muscleGroupIcon(for: exercise.muscleGroup))
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
                    .frame(width: 40, height: 40)
                    .background(.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(routineExercise.exercise?.name ?? "Unknown")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    Text("\(routineExercise.sets.count)")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                    Text(routineExercise.sets.count == 1 ? "set" : "sets")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .contentShape(Rectangle())
    }

    private func muscleGroupIcon(for group: String?) -> String {
        switch group {
        case "Arms": return "figure.arms.open"
        case "Legs": return "figure.walk"
        case "Chest": return "figure.strengthtraining.traditional"
        case "Back": return "figure.cooldown"
        case "Shoulders": return "figure.flexibility"
        case "Core": return "figure.core.training"
        case "Glutes": return "figure.run"
        case "Calves": return "figure.stairs"
        case "Full Body": return "figure.mixed.cardio"
        default: return "dumbbell.fill"
        }
    }
}

struct RoutineSetRowView: View {
    let set: ExerciseSet
    let index: Int
    let isExpanded: Bool
    @Binding var editingReps: Int
    @Binding var editingWeight: Double
    @Binding var editingRestTime: TimeInterval
    let onTap: () -> Void
    let onUpdate: (Int, Double, TimeInterval) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Set header
            Button(action: onTap) {
                HStack(spacing: 12) {
                    // Set number badge
                    Text("\(index + 1)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(.blue)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(set.reps) reps × \(set.weight, specifier: "%.1f") kg")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)

                        Text("Rest: \(formatRestTime(set.restTime))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded edit form
            if isExpanded {
                VStack(spacing: 12) {
                    HStack {
                        Text("Reps:")
                        Spacer()
                        Stepper("\(editingReps)", value: $editingReps, in: 1...100)
                            .onChange(of: editingReps) { _, newValue in
                                onUpdate(newValue, editingWeight, editingRestTime)
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
                                onUpdate(editingReps, newValue, editingRestTime)
                            }
                    }

                    HStack {
                        Text("Rest Time:")
                        Spacer()
                        Text(formatRestTime(editingRestTime))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $editingRestTime, in: 0...300, step: 30)
                        .onChange(of: editingRestTime) { _, newValue in
                            let rounded = round(newValue / 30) * 30
                            if rounded != editingRestTime {
                                editingRestTime = rounded
                            }
                            onUpdate(editingReps, editingWeight, rounded)
                        }
                }
                .padding(.leading, 40)
                .padding(.top, 8)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                ))
            }
        }
        .padding(.vertical, 4)
    }

    private func formatRestTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }
}

// MARK: - Edit Routine Name Sheet

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
