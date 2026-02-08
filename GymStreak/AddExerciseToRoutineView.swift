import SwiftUI
import SwiftData

struct AddExerciseToRoutineView: View {
    let routine: Routine
    @ObservedObject var viewModel: RoutinesViewModel
    @ObservedObject var exercisesViewModel: ExercisesViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var exercises: [Exercise] = []
    @State private var searchText = ""
    @State private var navigationPath = NavigationPath()

    var filteredExercises: [Exercise] {
        if searchText.isEmpty {
            return exercises
        } else {
            return exercises.filter { exercise in
                exercise.name.localizedCaseInsensitiveContains(searchText) ||
                exercise.muscleGroups.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
    }

    private func isExerciseAlreadyInRoutine(_ exercise: Exercise) -> Bool {
        routine.routineExercisesList.contains(where: { $0.exercise?.id == exercise.id })
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                // Section 1: Already in Routine
                let alreadyAddedExercises = filteredExercises.filter { isExerciseAlreadyInRoutine($0) }
                if !alreadyAddedExercises.isEmpty {
                    Section {
                        ForEach(alreadyAddedExercises) { exercise in
                            HStack(spacing: 12) {
                                // Muscle group badge (subdued)
                                MuscleGroupAbbreviationBadge(
                                    muscleGroups: exercise.muscleGroups,
                                    isActive: false
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(exercise.name)
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                    Text(MuscleGroups.displayString(for: exercise.muscleGroups))
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }

                                Spacer()

                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.title3)
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color(.secondarySystemGroupedBackground))
                            .accessibilityLabel("\(exercise.name), \(MuscleGroups.displayString(for: exercise.muscleGroups)), already in routine")
                            .accessibilityHint("This exercise is already in your routine")
                        }
                    } header: {
                        Label("add_to_routine.already_added".localized, systemImage: "checkmark.circle.fill")
                    }
                }

                // Section 2: Available Exercises
                let availableExercises = filteredExercises.filter { !isExerciseAlreadyInRoutine($0) }
                if !availableExercises.isEmpty {
                    Section("add_to_routine.available".localized) {
                        ForEach(availableExercises) { exercise in
                            NavigationLink(value: exercise) {
                                HStack(spacing: 12) {
                                    // Muscle group badge (active)
                                    MuscleGroupAbbreviationBadge(
                                        muscleGroups: exercise.muscleGroups,
                                        isActive: true
                                    )

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(exercise.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text(MuscleGroups.displayString(for: exercise.muscleGroups))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                            .accessibilityLabel("Add \(exercise.name), \(MuscleGroups.displayString(for: exercise.muscleGroups)) to routine")
                            .accessibilityHint("Opens configuration screen to add sets")
                        }
                    }
                }

                Section {
                    NavigationLink(value: "createNewExercise") {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.accentColor)
                            Text("add_to_routine.create_new".localized)
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("add_to_routine.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "add_to_routine.search".localized)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("action.cancel".localized) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                fetchExercises()
            }
            .navigationDestination(for: Exercise.self) { exercise in
                ConfigureExerciseSetsView(
                    exercise: exercise,
                    routine: routine,
                    viewModel: viewModel,
                    onSave: {
                        dismiss()
                    }
                )
            }
            .navigationDestination(for: String.self) { destination in
                if destination == "createNewExercise" {
                    CreateExerciseInlineView(
                        exercisesViewModel: exercisesViewModel,
                        onExerciseCreated: { newExercise in
                            // Pop back and push to configure view
                            navigationPath.removeLast()
                            fetchExercises()
                            navigationPath.append(newExercise)
                        }
                    )
                }
            }
        }
    }

    private func fetchExercises() {
        let descriptor = FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name, order: .forward)])
        do {
            exercises = try modelContext.fetch(descriptor)
        } catch {
            print("Error fetching exercises: \(error)")
        }
    }
}

// MARK: - Configure Exercise Sets View
struct ConfigureExerciseSetsView: View {
    let exercise: Exercise
    let routine: Routine
    @ObservedObject var viewModel: RoutinesViewModel
    var onSave: () -> Void

    @State private var sets: [ExerciseSet] = []
    @State private var globalRestTime: TimeInterval = 0.0
    // Use UUID-based tracking (same pattern as RoutineDetailView/RoutineExerciseDetailView)
    @State private var editingSetId: UUID?
    @State private var editingReps = 10
    @State private var editingWeight = 0.0
    @State private var initialReps = 10
    @State private var initialWeight = 0.0
    @State private var bannerDismissed = false

    // Computed property to check if values have changed
    private var hasChanges: Bool {
        editingReps != initialReps || editingWeight != initialWeight
    }

    // Save current editing set by UUID (same pattern as RoutineExerciseDetailView)
    private func saveCurrentEditingSet() {
        guard let currentId = editingSetId,
              let currentSet = sets.first(where: { $0.id == currentId }) else { return }
        if currentSet.reps != editingReps || currentSet.weight != editingWeight {
            currentSet.reps = editingReps
            currentSet.weight = editingWeight
        }
    }

    // Helper to get index for display purposes
    private func index(of set: ExerciseSet) -> Int {
        sets.firstIndex(where: { $0.id == set.id }) ?? 0
    }

    var body: some View {
        List {
            Section("configure_exercise.info".localized) {
                HStack {
                    Text("exercises.name".localized)
                    Spacer()
                    Text(exercise.name)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("exercises.muscle_groups".localized)
                    Spacer()
                    Text(MuscleGroups.displayString(for: exercise.muscleGroups))
                        .foregroundColor(.secondary)
                }
            }

            Section("configure_exercise.sets".localized) {
                ForEach(sets) { set in
                    VStack(alignment: .leading, spacing: 0) {
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
                                    initialReps = set.reps
                                    initialWeight = set.weight
                                    // Reset banner dismissed state when opening a new set
                                    bannerDismissed = false
                                }
                            }
                        }) {
                            HStack {
                                Text("Set \(index(of: set) + 1)")
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

                        if editingSetId == set.id {
                            VStack(spacing: 12) {
                                // Apply to All Banner (only if multiple sets AND changes were made AND not dismissed)
                                if sets.count > 1 && hasChanges && !bannerDismissed {
                                    ApplyToAllBanner(
                                        setCount: sets.count,
                                        onApply: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                // Apply to all sets
                                                for s in sets {
                                                    s.reps = editingReps
                                                    s.weight = editingWeight
                                                }
                                                bannerDismissed = true
                                            }
                                        },
                                        onDismiss: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                bannerDismissed = true
                                            }
                                        }
                                    )
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .top).combined(with: .opacity),
                                        removal: .move(edge: .top).combined(with: .opacity)
                                    ))
                                }

                                HorizontalStepper(
                                    title: "Reps",
                                    value: $editingReps,
                                    range: 1...100,
                                    step: 1
                                ) { _ in
                                    // Guard: only process updates for the currently expanded set
                                    guard editingSetId == set.id else { return }
                                    updateSet(set)
                                }

                                WeightInput(
                                    title: "Weight (kg)",
                                    weight: $editingWeight,
                                    increment: 0.25
                                ) { _ in
                                    // Guard: only process updates for the currently expanded set
                                    guard editingSetId == set.id else { return }
                                    updateSet(set)
                                }
                            }
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                                removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                            ))
                        }
                    }
                }
                .onDelete(perform: deleteSets)

                VStack(spacing: 4) {
                    Button(action: addNewSet) {
                        Text("exercise.add_set".localized)
                            .foregroundColor(DesignSystem.Colors.tint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(DesignSystem.Colors.tint.opacity(0.1))
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
        .navigationTitle("add_to_routine.add_title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("action.save".localized) {
                    saveExerciseToRoutine()
                }
                .disabled(sets.isEmpty)
            }
        }
    }

    private func addNewSet() {
        // Save current editing set before adding new one
        saveCurrentEditingSet()

        let order = sets.count
        let newSet = ExerciseSet(reps: 10, weight: 0.0, restTime: globalRestTime, order: order)
        sets.append(newSet)

        withAnimation(.easeInOut(duration: 0.3)) {
            editingSetId = newSet.id
            editingReps = newSet.reps
            editingWeight = newSet.weight
            initialReps = newSet.reps
            initialWeight = newSet.weight
            bannerDismissed = false
        }
    }

    private func duplicateLastSet() {
        // Save current editing set before duplicating
        saveCurrentEditingSet()

        guard let lastSet = sets.last else { return }

        // If the last set is currently being edited, use editing values
        let repsToUse: Int
        let weightToUse: Double

        if editingSetId == lastSet.id {
            repsToUse = editingReps
            weightToUse = editingWeight
        } else {
            repsToUse = lastSet.reps
            weightToUse = lastSet.weight
        }

        let order = sets.count
        let newSet = ExerciseSet(reps: repsToUse, weight: weightToUse, restTime: globalRestTime, order: order)
        sets.append(newSet)

        withAnimation(.easeInOut(duration: 0.3)) {
            editingSetId = newSet.id
            editingReps = newSet.reps
            editingWeight = newSet.weight
            initialReps = newSet.reps
            initialWeight = newSet.weight
            bannerDismissed = false
        }
    }

    private func updateSet(_ set: ExerciseSet) {
        set.reps = editingReps
        set.weight = editingWeight
    }

    private func deleteSets(offsets: IndexSet) {
        // Check if we're deleting the currently editing set
        for index in offsets {
            if sets[index].id == editingSetId {
                editingSetId = nil
                break
            }
        }
        sets.remove(atOffsets: offsets)
    }

    private func saveExerciseToRoutine() {
        // Save any pending edits before saving
        saveCurrentEditingSet()
        let routineExercise = RoutineExercise(exercise: exercise, order: routine.routineExercisesList.count)
        routineExercise.routine = routine

        for (index, set) in sets.enumerated() {
            set.restTime = globalRestTime
            set.order = index
            set.routineExercise = routineExercise
            routineExercise.sets?.append(set)
        }

        routine.routineExercises?.append(routineExercise)
        viewModel.updateRoutine(routine)

        onSave()
    }
}

// MARK: - Create Exercise Inline View
struct CreateExerciseInlineView: View {
    @ObservedObject var exercisesViewModel: ExercisesViewModel
    var onExerciseCreated: (Exercise) -> Void

    @State private var exerciseName = ""
    @State private var muscleGroups: [String] = ["Chest"]

    var body: some View {
        Form {
            Section {
                TextField("exercises.name".localized, text: $exerciseName)

                MuscleGroupPicker(selectedMuscleGroups: $muscleGroups)
            }
        }
        .navigationTitle("add_exercise.title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("action.save".localized) {
                    saveExercise()
                }
                .disabled(exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || muscleGroups.isEmpty)
            }
        }
    }

    private func saveExercise() {
        let trimmedName = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let newExercise = exercisesViewModel.addExercise(
            name: trimmedName,
            muscleGroups: muscleGroups
        ) {
            onExerciseCreated(newExercise)
        }
    }
}

#Preview {
    Text("AddExerciseToRoutineView Preview")
}
