import SwiftUI

struct RoutineDetailView: View {
    let routine: Routine
    @ObservedObject var viewModel: RoutinesViewModel
    @ObservedObject var exercisesViewModel: ExercisesViewModel
    @ObservedObject var workoutViewModel: WorkoutViewModel
    @State private var showingAddExercise = false
    @State private var showingDeleteAlert = false
    @State private var showingEditRoutine = false
    @State private var showingActiveWorkout = false
    @State private var expandedExerciseId: UUID?
    @State private var expandedSetId: UUID?
    @State private var editingReps: Int = 10
    @State private var editingWeight: Double = 0.0
    @State private var initialReps: Int = 10
    @State private var initialWeight: Double = 0.0
    @State private var exerciseRestTimes: [UUID: TimeInterval] = [:]
    @State private var repsBannerDismissedForExercise: [UUID: Bool] = [:]
    @State private var weightBannerDismissedForExercise: [UUID: Bool] = [:]
    @State private var currentRoutineExercise: RoutineExercise?

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
                                            // Initialize rest time for this exercise if not set
                                            if exerciseRestTimes[routineExercise.id] == nil,
                                               let firstSet = routineExercise.sets.first {
                                                exerciseRestTimes[routineExercise.id] = firstSet.restTime
                                            }
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
                                        initialReps: initialReps,
                                        initialWeight: initialWeight,
                                        hasMultipleSets: routineExercise.sets.count > 1,
                                        repsBannerDismissed: repsBannerDismissedForExercise[routineExercise.id] ?? false,
                                        weightBannerDismissed: weightBannerDismissedForExercise[routineExercise.id] ?? false,
                                        totalSets: routineExercise.sets.count,
                                        onTap: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                if expandedSetId == set.id {
                                                    expandedSetId = nil
                                                    currentRoutineExercise = nil
                                                } else {
                                                    expandedSetId = set.id
                                                    editingReps = set.reps
                                                    editingWeight = set.weight
                                                    initialReps = set.reps
                                                    initialWeight = set.weight
                                                    currentRoutineExercise = routineExercise
                                                    // Reset banner dismissed states when opening a new set
                                                    repsBannerDismissedForExercise[routineExercise.id] = false
                                                    weightBannerDismissedForExercise[routineExercise.id] = false
                                                }
                                            }
                                        },
                                        onUpdate: { reps, weight in
                                            handleSetUpdate(
                                                set: set,
                                                reps: reps,
                                                weight: weight,
                                                routineExercise: routineExercise,
                                                applyToAll: false
                                            )
                                        },
                                        onApplyRepsToAll: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                handleApplyRepsToAll(
                                                    reps: editingReps,
                                                    routineExercise: routineExercise
                                                )
                                                repsBannerDismissedForExercise[routineExercise.id] = true
                                                initialReps = editingReps
                                            }
                                        },
                                        onApplyWeightToAll: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                handleApplyWeightToAll(
                                                    weight: editingWeight,
                                                    routineExercise: routineExercise
                                                )
                                                weightBannerDismissedForExercise[routineExercise.id] = true
                                                initialWeight = editingWeight
                                            }
                                        },
                                        onDismissRepsBanner: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                repsBannerDismissedForExercise[routineExercise.id] = true
                                            }
                                        },
                                        onDismissWeightBanner: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                weightBannerDismissedForExercise[routineExercise.id] = true
                                            }
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

                                // Global Rest Timer for this exercise
                                Divider()
                                    .padding(.vertical, 4)

                                VStack(spacing: 8) {
                                    HStack {
                                        Text("Rest Time Between Sets")
                                            .font(.subheadline.weight(.medium))
                                        Spacer()
                                        Text(TimeFormatting.formatRestTime(exerciseRestTimes[routineExercise.id] ?? 60))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    Slider(
                                        value: Binding(
                                            get: { exerciseRestTimes[routineExercise.id] ?? 60 },
                                            set: { newValue in
                                                let rounded = round(newValue / 30) * 30
                                                exerciseRestTimes[routineExercise.id] = rounded
                                                updateAllSetsRestTime(for: routineExercise, restTime: rounded)
                                            }
                                        ),
                                        in: 0...300,
                                        step: 30
                                    )
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color(.tertiarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
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
        .safeAreaInset(edge: .bottom) {
            if !routine.routineExercises.isEmpty {
                VStack(spacing: 0) {
                    Divider()
                    Button {
                        workoutViewModel.startWorkout(routine: routine)
                        showingActiveWorkout = true
                    } label: {
                        Label("Start Workout", systemImage: "play.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial)
                }
            }
        }
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
        .fullScreenCover(isPresented: $showingActiveWorkout) {
            ActiveWorkoutView(viewModel: workoutViewModel)
        }
    }

    private func deleteRoutineExercises(offsets: IndexSet) {
        for index in offsets {
            let routineExercise = routine.routineExercises.sorted(by: { $0.order < $1.order })[index]
            viewModel.removeRoutineExercise(routineExercise, from: routine)
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

    private func updateAllSetsRestTime(for routineExercise: RoutineExercise, restTime: TimeInterval) {
        for set in routineExercise.sets {
            set.restTime = restTime
            viewModel.updateSet(set)
        }
    }

    private func handleSetUpdate(
        set: ExerciseSet,
        reps: Int?,
        weight: Double?,
        routineExercise: RoutineExercise,
        applyToAll: Bool
    ) {
        if applyToAll {
            // Apply to all sets in this exercise
            for exerciseSet in routineExercise.sets {
                if let reps = reps {
                    exerciseSet.reps = reps
                }
                if let weight = weight {
                    exerciseSet.weight = weight
                }
                viewModel.updateSet(exerciseSet)
            }
        } else {
            // Apply only to current set
            updateSet(set, reps: reps, weight: weight)
        }
    }

    private func handleApplyRepsToAll(reps: Int, routineExercise: RoutineExercise) {
        for exerciseSet in routineExercise.sets {
            exerciseSet.reps = reps
            viewModel.updateSet(exerciseSet)
        }
    }

    private func handleApplyWeightToAll(weight: Double, routineExercise: RoutineExercise) {
        for exerciseSet in routineExercise.sets {
            exerciseSet.weight = weight
            viewModel.updateSet(exerciseSet)
        }
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
        guard let group = group else { return "dumbbell.fill" }
        return MuscleGroups.icon(for: group)
    }
}

struct RoutineSetRowView: View {
    let set: ExerciseSet
    let index: Int
    let isExpanded: Bool
    @Binding var editingReps: Int
    @Binding var editingWeight: Double
    let initialReps: Int
    let initialWeight: Double
    let hasMultipleSets: Bool
    let repsBannerDismissed: Bool
    let weightBannerDismissed: Bool
    let totalSets: Int
    let onTap: () -> Void
    let onUpdate: (Int, Double) -> Void
    let onApplyRepsToAll: () -> Void
    let onApplyWeightToAll: () -> Void
    let onDismissRepsBanner: () -> Void
    let onDismissWeightBanner: () -> Void

    // Computed property to check if reps have changed
    private var repsChanged: Bool {
        editingReps != initialReps
    }

    // Computed property to check if weight has changed
    private var weightChanged: Bool {
        editingWeight != initialWeight
    }

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
                        Text("\(set.reps) reps × \(set.weight, specifier: "%.2f") kg")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)

                        Text("Rest: \(TimeFormatting.formatRestTime(set.restTime))")
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
                    VStack(spacing: 16) {
                        // Reps input with contextual banner
                        VStack(spacing: 8) {
                            HorizontalStepper(
                                title: "Reps",
                                value: $editingReps,
                                range: 1...100,
                                step: 1
                            ) { newValue in
                                onUpdate(newValue, editingWeight)
                            }

                            // Reps Apply to All Banner
                            if hasMultipleSets && repsChanged && !repsBannerDismissed {
                                ApplyToAllBanner(
                                    type: .reps,
                                    setCount: totalSets,
                                    onApply: onApplyRepsToAll,
                                    onDismiss: onDismissRepsBanner
                                )
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                ))
                            }
                        }

                        // Weight input with contextual banner
                        VStack(spacing: 8) {
                            WeightInput(
                                title: "Weight (kg)",
                                weight: $editingWeight,
                                increment: 0.25
                            ) { newValue in
                                onUpdate(editingReps, newValue)
                            }

                            // Weight Apply to All Banner
                            if hasMultipleSets && weightChanged && !weightBannerDismissed {
                                ApplyToAllBanner(
                                    type: .weight,
                                    setCount: totalSets,
                                    onApply: onApplyWeightToAll,
                                    onDismiss: onDismissWeightBanner
                                )
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                ))
                            }
                        }
                    }
                    .padding(.leading, 40)
                    .padding(.trailing, 16)
                }
                .padding(.top, 12)
                .padding(.bottom, 8)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                ))
            }
        }
        .padding(.vertical, 4)
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
