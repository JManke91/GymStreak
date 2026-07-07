import SwiftUI

struct AddExerciseToRoutineView: View {
    let routine: Routine
    @ObservedObject var viewModel: RoutinesViewModel
    @ObservedObject var exercisesViewModel: ExercisesViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dependencies: AppDependencies

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
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        RedesignSearchBar(text: $searchText, placeholder: "add_to_routine.search".localized)
                            .padding(.horizontal, 18)
                            .padding(.top, 8)

                        // Section 1: Available Exercises
                        let availableExercises = filteredExercises.filter { !isExerciseAlreadyInRoutine($0) }
                        if !availableExercises.isEmpty {
                            pickerSectionLabel("add_to_routine.available".localized)
                            VStack(spacing: 7) {
                                ForEach(availableExercises) { exercise in
                                    NavigationLink(value: exercise) {
                                        pickerRow(exercise, disabled: false)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(exercise.name), \(MuscleGroups.displayString(for: exercise.muscleGroups))")
                                    .accessibilityHint("Opens configuration screen to add sets")
                                }
                            }
                            .padding(.horizontal, 18)
                        }

                        // Section 2: Already in Routine
                        let alreadyAddedExercises = filteredExercises.filter { isExerciseAlreadyInRoutine($0) }
                        if !alreadyAddedExercises.isEmpty {
                            pickerSectionLabel("add_to_routine.already_added".localized)
                            VStack(spacing: 7) {
                                ForEach(alreadyAddedExercises) { exercise in
                                    pickerRow(exercise, disabled: true)
                                        .accessibilityLabel("\(exercise.name), \(MuscleGroups.displayString(for: exercise.muscleGroups)), already in routine")
                                        .accessibilityHint("This exercise is already in your routine")
                                }
                            }
                            .padding(.horizontal, 18)
                        }

                        NavigationLink(value: "createNewExercise") {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .bold))
                                Text("add_to_routine.create_new".localized)
                                    .font(.system(size: 13.5, weight: .bold))
                            }
                            .foregroundStyle(DesignSystem.Colors.tint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                                    .foregroundStyle(DesignSystem.Colors.tint.opacity(0.5))
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 18)
                        .padding(.top, 18)

                        Color.clear.frame(height: 40)
                    }
                }
            }
            .navigationTitle("add_to_routine.title".localized)
            .navigationBarTitleDisplayMode(.inline)
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
                    AddExerciseView(
                        viewModel: exercisesViewModel,
                        presentationMode: .navigation,
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
        exercises = dependencies.exerciseRepository.fetchAll()
    }

    private func pickerSectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .kerning(0.7)
            .foregroundStyle(Color.white.opacity(0.45))
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pickerRow(_ exercise: Exercise, disabled: Bool) -> some View {
        HStack(spacing: 12) {
            ExerciseAvatarView(
                muscleGroups: exercise.muscleGroups,
                equipmentType: exercise.equipmentType,
                size: 38
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(MuscleGroups.displayName(for: exercise.primaryMuscleGroup))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.5))
                    EquipmentTagView(equipmentType: exercise.equipmentType)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: disabled ? "checkmark" : "plus")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(disabled ? Color.white.opacity(0.4) : DesignSystem.Colors.tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(disabled ? 0.45 : 1)
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
    // Alternative exercises picked before save; materialized on Save
    @State private var pendingAlternatives: [PendingAlternative] = []
    @State private var showingAlternativePicker = false
    @State private var expandedAlternativeId: UUID?

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

            PendingAlternativesSection(
                primaryExercise: exercise,
                alternatives: $pendingAlternatives,
                showingPicker: $showingAlternativePicker,
                expandedAlternativeId: $expandedAlternativeId
            )
        }
        .navigationDestination(isPresented: $showingAlternativePicker) {
            AlternativeExercisePicker(
                primaryExercise: exercise,
                excludedExerciseIds: Set(pendingAlternatives.map { $0.exercise.id }).union([exercise.id]),
                onSelect: { picked in
                    saveCurrentEditingSet()
                    let alternative = PendingAlternative(exercise: picked, seededFrom: sets, restTime: globalRestTime)
                    pendingAlternatives.append(alternative)
                    // Expand the new alternative's inline editor so its reps and
                    // weight can be defined right away
                    expandedAlternativeId = alternative.id
                    showingAlternativePicker = false
                }
            )
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

        // Materialize picked alternatives now that the routine exercise is attached
        // to the persisted routine, keeping each alternative's own set scheme.
        for pending in pendingAlternatives {
            viewModel.addAlternative(pending.exercise, to: routineExercise, copying: pending.sets)
        }

        viewModel.updateRoutine(routine)

        onSave()
    }
}

#Preview {
    Text("AddExerciseToRoutineView Preview")
}
