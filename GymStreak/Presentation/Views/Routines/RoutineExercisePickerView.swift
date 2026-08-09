import SwiftUI

struct RoutineExercisePickerView: View {
    /// Exercises already part of the target routine/draft; shown dimmed and unselectable.
    let alreadyAddedExercises: [Exercise]
    @ObservedObject var exercisesViewModel: ExercisesViewModel
    /// Name of the routine being added to — the configure screen's CTA names it.
    /// `nil` while a new routine is still unnamed.
    var routineName: String? = nil
    /// Called with the fully configured selection (exercise, finalized sets,
    /// pending alternatives, rep-range goal); the caller owns persistence.
    /// Dismisses afterwards.
    var onExerciseConfigured: (Exercise, [ExerciseSet], [PendingAlternative], Int?, Int?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedCategoryKey: String?
    @State private var navigationPath = NavigationPath()
    @FocusState private var isSearchFocused: Bool

    /// Search + muscle-category filtering reuses the ViewModel's library logic
    /// (same behavior as the Exercises tab), flattened to a single list; the
    /// picker applies its own Available / Already-in-Routine sectioning below.
    var filteredExercises: [Exercise] {
        exercisesViewModel
            .sections(searchText: searchText, categoryKey: selectedCategoryKey, equipment: nil)
            .flatMap(\.exercises)
    }

    private func isExerciseAlreadyInRoutine(_ exercise: Exercise) -> Bool {
        alreadyAddedExercises.contains(where: { $0.id == exercise.id })
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        RedesignSearchBar(text: $searchText, placeholder: "add_to_routine.search".localized, isFocused: $isSearchFocused)
                            .padding(.horizontal, 18)
                            .padding(.top, 8)

                        // Muscle category filter (mirrors the Exercises tab)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 7) {
                                FilterPillButton(label: "filter.all".localized, isActive: selectedCategoryKey == nil) {
                                    withAnimation(.easeOut(duration: 0.15)) { selectedCategoryKey = nil }
                                }
                                ForEach(exercisesViewModel.availableCategoryKeys, id: \.self) { categoryKey in
                                    FilterPillButton(
                                        label: categoryKey.localized,
                                        isActive: selectedCategoryKey == categoryKey,
                                        color: MuscleGroups.categoryColor(for: categoryKey)
                                    ) {
                                        withAnimation(.easeOut(duration: 0.15)) {
                                            selectedCategoryKey = selectedCategoryKey == categoryKey ? nil : categoryKey
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 18)
                        }
                        .padding(.top, 12)

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
            .keyboardDoneBar(isFocused: $isSearchFocused)
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
                exercisesViewModel.fetchExercises()
            }
            .navigationDestination(for: Exercise.self) { exercise in
                ConfigureExerciseSetsView(
                    exercise: exercise,
                    destinationName: routineName,
                    onSave: { exercise, sets, alternatives, repMin, repMax in
                        onExerciseConfigured(exercise, sets, alternatives, repMin, repMax)
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
                            // (the ViewModel already refreshed its library on creation)
                            navigationPath.removeLast()
                            navigationPath.append(newExercise)
                        }
                    )
                }
            }
        }
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

#Preview {
    Text("RoutineExercisePickerView Preview")
}
