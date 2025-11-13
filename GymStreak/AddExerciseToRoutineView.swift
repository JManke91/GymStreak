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

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                Section("Choose Exercise") {
                    ForEach(filteredExercises) { exercise in
                        NavigationLink(value: exercise) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                HStack {
                                    Text(exercise.muscleGroup)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if !exercise.exerciseDescription.isEmpty {
                                        Text("•")
                                            .foregroundColor(.secondary)
                                        Text(exercise.exerciseDescription)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    NavigationLink(value: "createNewExercise") {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.accentColor)
                            Text("Create New Exercise")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
            .navigationTitle("Choose Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search exercises or muscle groups")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
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
    @State private var globalRestTime: TimeInterval = 60.0
    @State private var editingSetIndex: Int?
    @State private var editingReps = 10
    @State private var editingWeight = 0.0

    var body: some View {
        List {
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
                    HStack {
                        Text("Description")
                        Spacer()
                        Text(exercise.exerciseDescription)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            Section("Sets") {
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
        .navigationTitle("Add to Routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
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
        }
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

    private let muscleGroups = ["General", "Arms", "Legs", "Chest", "Back", "Shoulders", "Core", "Glutes", "Calves", "Full Body"]

    var body: some View {
        Form {
            Section("Exercise Details") {
                TextField("Exercise Name", text: $exerciseName)

                Picker("Muscle Group", selection: $muscleGroup) {
                    ForEach(muscleGroups, id: \.self) { muscleGroup in
                        Text(muscleGroup).tag(muscleGroup)
                    }
                }

                TextField("Description (Optional)", text: $exerciseDescription, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle("New Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
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
