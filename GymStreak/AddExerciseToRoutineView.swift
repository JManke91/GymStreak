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
                exercise.muscleGroup.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private func isExerciseAlreadyInRoutine(_ exercise: Exercise) -> Bool {
        routine.routineExercises.contains(where: { $0.exercise?.id == exercise.id })
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
                                // Muscle group icon (subdued)
                                Image(systemName: MuscleGroups.icon(for: exercise.muscleGroup))
                                    .font(.title3)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, height: 40)
                                    .background(Color.secondary.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(exercise.name)
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        Text(exercise.muscleGroup)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                        if !exercise.exerciseDescription.isEmpty {
                                            Text("•")
                                                .foregroundStyle(.tertiary)
                                            Text(exercise.exerciseDescription)
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(1)
                                        }
                                    }
                                }

                                Spacer()

                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.title3)
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color(.secondarySystemGroupedBackground))
                            .accessibilityLabel("\(exercise.name), \(exercise.muscleGroup), already in routine")
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
                                    // Muscle group icon (active)
                                    Image(systemName: MuscleGroups.icon(for: exercise.muscleGroup))
                                        .font(.title3)
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(Color.appAccent)
                                        .frame(width: 40, height: 40)
                                        .background(Color.appAccent.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(exercise.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        HStack {
                                            Text(exercise.muscleGroup)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            if !exercise.exerciseDescription.isEmpty {
                                                Text("•")
                                                    .foregroundStyle(.secondary)
                                                Text(exercise.exerciseDescription)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 4)
                            }
                            .accessibilityLabel("Add \(exercise.name), \(exercise.muscleGroup) to routine")
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
    @State private var editingSetIndex: Int?
    @State private var editingReps = 10
    @State private var editingWeight = 0.0
    @State private var initialReps = 10
    @State private var initialWeight = 0.0
    @State private var bannerDismissed = false

    // Computed property to check if values have changed
    private var hasChanges: Bool {
        editingReps != initialReps || editingWeight != initialWeight
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
                    Text("exercises.muscle_group".localized)
                    Spacer()
                    Text(exercise.muscleGroup)
                        .foregroundColor(.secondary)
                }

                if !exercise.exerciseDescription.isEmpty {
                    HStack {
                        Text("exercises.description".localized)
                        Spacer()
                        Text(exercise.exerciseDescription)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            Section("configure_exercise.sets".localized) {
                ForEach(Array(sets.enumerated()), id: \.offset) { index, set in
                    VStack(alignment: .leading, spacing: 0) {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                if editingSetIndex == index {
                                    editingSetIndex = nil
                                } else {
                                    editingSetIndex = index
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

                        if editingSetIndex == index {
                            VStack(spacing: 12) {
                                // Apply to All Banner (only if multiple sets AND changes were made AND not dismissed)
                                if sets.count > 1 && hasChanges && !bannerDismissed {
                                    ApplyToAllBanner(
                                        setCount: sets.count,
                                        onApply: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                // Apply to all sets
                                                for i in sets.indices {
                                                    sets[i].reps = editingReps
                                                    sets[i].weight = editingWeight
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
                                    handleSetUpdate(at: index)
                                }

                                WeightInput(
                                    title: "Weight (kg)",
                                    weight: $editingWeight,
                                    increment: 0.25
                                ) { _ in
                                    handleSetUpdate(at: index)
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
        let newSet = ExerciseSet(reps: 10, weight: 0.0, restTime: globalRestTime)
        sets.append(newSet)

        withAnimation(.easeInOut(duration: 0.3)) {
            editingSetIndex = sets.count - 1
            editingReps = newSet.reps
            editingWeight = newSet.weight
            initialReps = newSet.reps
            initialWeight = newSet.weight
        }
    }

    private func duplicateLastSet() {
        guard let lastSet = sets.last else { return }

        let repsToUse: Int
        let weightToUse: Double

        if let editingIndex = editingSetIndex, editingIndex == sets.count - 1 {
            repsToUse = editingReps
            weightToUse = editingWeight
        } else {
            repsToUse = lastSet.reps
            weightToUse = lastSet.weight
        }

        let newSet = ExerciseSet(reps: repsToUse, weight: weightToUse, restTime: globalRestTime)
        sets.append(newSet)

        withAnimation(.easeInOut(duration: 0.3)) {
            editingSetIndex = sets.count - 1
            editingReps = newSet.reps
            editingWeight = newSet.weight
            initialReps = newSet.reps
            initialWeight = newSet.weight
        }
    }

    private func handleSetUpdate(at index: Int) {
        // Apply only to current set (Apply to All is handled by the banner callback)
        updateSet(at: index)
    }

    private func updateSet(at index: Int) {
        guard index < sets.count else { return }
        sets[index].reps = editingReps
        sets[index].weight = editingWeight
    }

    private func deleteSets(offsets: IndexSet) {
        sets.remove(atOffsets: offsets)
        if let editingIndex = editingSetIndex, editingIndex >= sets.count {
            editingSetIndex = nil
        }
    }

    private func saveExerciseToRoutine() {
        let routineExercise = RoutineExercise(exercise: exercise, order: routine.routineExercises.count)
        routineExercise.routine = routine

        for set in sets {
            set.restTime = globalRestTime
            set.routineExercise = routineExercise
            routineExercise.sets.append(set)
        }

        routine.routineExercises.append(routineExercise)
        viewModel.updateRoutine(routine)

        onSave()
    }
}

// MARK: - Create Exercise Inline View
struct CreateExerciseInlineView: View {
    @ObservedObject var exercisesViewModel: ExercisesViewModel
    var onExerciseCreated: (Exercise) -> Void

    @State private var exerciseName = ""
    @State private var muscleGroup = "General"
    @State private var exerciseDescription = ""

    var body: some View {
        Form {
            Section {
                TextField("exercises.name".localized, text: $exerciseName)

                Picker("exercises.muscle_group".localized, selection: $muscleGroup) {
                    ForEach(MuscleGroups.all, id: \.self) { muscleGroup in
                        Text(muscleGroup).tag(muscleGroup)
                    }
                }

                TextField("add_exercise.description_optional".localized, text: $exerciseDescription, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle("add_exercise.title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("action.save".localized) {
                    saveExercise()
                }
                .disabled(exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func saveExercise() {
        let trimmedName = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let newExercise = exercisesViewModel.addExercise(
            name: trimmedName,
            muscleGroup: muscleGroup,
            exerciseDescription: exerciseDescription
        ) {
            onExerciseCreated(newExercise)
        }
    }
}

#Preview {
    Text("AddExerciseToRoutineView Preview")
}
