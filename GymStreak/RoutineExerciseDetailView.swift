import SwiftUI

struct RoutineExerciseDetailView: View {
    @Bindable var routineExercise: RoutineExercise
    @ObservedObject var viewModel: RoutinesViewModel
    @State private var showingEditExercise = false
    @State private var showingDeleteAlert = false
    @State private var editingSetId: UUID?
    @State private var editingReps: Int = 10
    @State private var editingWeight: Double = 0.0
    @State private var restTimerExpanded = false

    // Computed property to get current rest time from sets
    private var globalRestTime: TimeInterval {
        routineExercise.setsList.first?.restTime ?? 0.0
    }
    
    var body: some View {
        List {
            Section("routine_exercise_detail.section.info".localized) {
                if let exercise = routineExercise.exercise {
                    HStack {
                        Text("routine_exercise_detail.label.name".localized)
                        Spacer()
                        Text(exercise.name)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("routine_exercise_detail.label.muscle_groups".localized)
                        Spacer()
                        Text(MuscleGroups.displayString(for: exercise.muscleGroups))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("routine_exercise_detail.error.not_found".localized)
                        .foregroundColor(.red)
                }

                HStack {
                    Text("routine_exercise_detail.label.sets".localized)
                    Spacer()
                    Text("\(routineExercise.setsList.count)")
                        .foregroundColor(.secondary)
                }
            }
            
            Section("routine_exercise_detail.section.sets".localized) {
                ForEach(Array(routineExercise.setsList.sorted(by: { $0.order < $1.order }).enumerated()), id: \.element.id) { index, set in
                    VStack(alignment: .leading, spacing: 0) {
                        // Collapsible set header
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                if editingSetId == set.id {
                                    // Save before collapsing
                                    saveCurrentEditingSet()
                                    editingSetId = nil
                                } else {
                                    // Save currently expanded set before switching
                                    saveCurrentEditingSet()
                                    // Expand and load values
                                    editingSetId = set.id
                                    editingReps = set.reps
                                    editingWeight = set.weight
                                }
                            }
                        }) {
                            HStack {
                                Text("routine_exercise_detail.set_number".localized(index + 1))
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("routine_exercise_detail.set_detail".localized(set.reps, set.weight))
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
                                    Text("routine_exercise_detail.reps_label".localized)
                                    Spacer()
                                    Stepper("\(editingReps)", value: $editingReps, in: 1...100)
                                        .onChange(of: editingReps) { _, newValue in
                                            guard editingSetId == set.id else { return }
                                            updateSet(set, reps: newValue)
                                        }
                                }

                                HStack {
                                    Text("routine_exercise_detail.weight_label".localized)
                                    Spacer()
                                    TextField("0.0", value: $editingWeight, format: .number)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .frame(width: 80)
                                        .onChange(of: editingWeight) { _, newValue in
                                            guard editingSetId == set.id else { return }
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

                Button("routine_exercise_detail.add_set".localized) {
                    addNewSet()
                }
                .foregroundColor(DesignSystem.Colors.tint)
            }

            Section {
                RestTimerConfigView(
                    restTime: Binding(
                        get: { globalRestTime },
                        set: { newValue in
                            updateAllSetsRestTime(newValue)
                        }
                    ),
                    isExpanded: $restTimerExpanded,
                    showToggle: true
                )
            } header: {
                Text("routine_exercise_detail.section.rest_timer".localized)
            }
        }
        .navigationTitle(routineExercise.exercise?.name ?? "Exercise")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("routine_exercise_detail.delete".localized, role: .destructive) {
                    showingDeleteAlert = true
                }
            }
        }
        .alert("routine_exercise_detail.delete_alert.title".localized, isPresented: $showingDeleteAlert) {
            Button("routine_exercise_detail.delete".localized, role: .destructive) {
                if let routine = routineExercise.routine {
                    viewModel.removeRoutineExercise(routineExercise, from: routine)
                }
            }
            Button("action.cancel".localized, role: .cancel) {}
        } message: {
            Text("routine_exercise_detail.delete_alert.message".localized)
        }
    }

    private func deleteSets(offsets: IndexSet) {
        let sortedSets = routineExercise.setsList.sorted(by: { $0.order < $1.order })
        for index in offsets {
            viewModel.removeSet(sortedSets[index], from: routineExercise)
        }
    }

    private func addNewSet() {
        viewModel.addSet(to: routineExercise)

        // Get the newly added set (last one)
        if let newSet = routineExercise.setsList.last {
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

    private func saveCurrentEditingSet() {
        guard let currentId = editingSetId,
              let currentSet = routineExercise.setsList.first(where: { $0.id == currentId }) else { return }
        if currentSet.reps != editingReps || currentSet.weight != editingWeight {
            currentSet.reps = editingReps
            currentSet.weight = editingWeight
            viewModel.updateSet(currentSet)
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
        for set in routineExercise.setsList {
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
