import SwiftUI

enum ExerciseFormPresentationMode {
    case sheet      // Standalone sheet with its own header (cancel/save)
    case navigation // Pushed onto a stack, uses nav toolbar save button
}

/// Redesigned exercise form: name card, multi-select muscle pills grouped by
/// category, equipment tiles and a live preview of the resulting library row.
/// Handles both creating a new exercise and editing an existing one.
struct AddExerciseView: View {
    @ObservedObject var viewModel: ExercisesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var exerciseName = ""
    @State private var muscleGroups: [String] = ["Chest"]
    @State private var equipmentType: EquipmentType = .dumbbell
    @State private var loadBehavior: ExerciseLoadBehavior = .resistance

    var presentationMode: ExerciseFormPresentationMode = .sheet
    var exerciseToEdit: Exercise? = nil
    var onExerciseCreated: ((Exercise) -> Void)?

    private var isEditing: Bool { exerciseToEdit != nil }

    private var canSave: Bool {
        !exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !muscleGroups.isEmpty
    }

    private var title: String {
        isEditing ? "exercise.edit".localized : "add_exercise.title".localized
    }

    // Categories offered for selection (General excluded, as before)
    private let selectableCategories: [MuscleGroups.Category] = MuscleGroups.categories
        .filter { $0.titleKey != "muscle_category.general" }

    var body: some View {
        Group {
            if presentationMode == .sheet {
                VStack(spacing: 0) {
                    sheetHeader
                    formContent
                }
                .background(Color(red: 22/255, green: 22/255, blue: 24/255))
            } else {
                ZStack {
                    DesignSystem.Colors.background.ignoresSafeArea()
                    formContent
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("action.save".localized) {
                            saveExercise()
                        }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                    }
                }
            }
        }
        .onAppear {
            if let exercise = exerciseToEdit {
                exerciseName = exercise.name
                muscleGroups = exercise.muscleGroups
                equipmentType = exercise.equipmentType
                loadBehavior = exercise.loadBehavior
            }
        }
    }

    // MARK: - Sheet header

    private var sheetHeader: some View {
        HStack {
            Button("action.cancel".localized) {
                dismiss()
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(DesignSystem.Colors.tint)
            .buttonStyle(.plain)

            Spacer()

            Text(title)
                .font(.system(size: 16, weight: .bold))
                .kerning(-0.3)
                .foregroundStyle(.white)

            Spacer()

            Button("action.save".localized) {
                saveExercise()
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(canSave ? DesignSystem.Colors.textOnTint : Color.white.opacity(0.35))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(canSave ? DesignSystem.Colors.tint : Color.white.opacity(0.08))
            .clipShape(Capsule())
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    // MARK: - Form

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Name
                TextField("add_exercise.name_placeholder".localized, text: $exerciseName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 15)
                    .background(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.bottom, 22)

                // Muscle groups (multi-select)
                formLabel("exercises.muscle_groups".localized)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(selectableCategories) { category in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(category.titleKey.localized.uppercased())
                                .font(.system(size: 9.5, weight: .bold))
                                .kerning(0.6)
                                .foregroundStyle(Color.white.opacity(0.3))
                            FlowLayout(spacing: 7) {
                                ForEach(category.muscleGroupKeys, id: \.self) { muscleGroup in
                                    FilterPillButton(
                                        label: MuscleGroups.displayName(for: muscleGroup),
                                        isActive: muscleGroups.contains(muscleGroup),
                                        color: MuscleGroups.color(for: muscleGroup)
                                    ) {
                                        toggleMuscleGroup(muscleGroup)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 22)

                formLabel("exercise.load_behavior".localized)
                Picker("exercise.load_behavior".localized, selection: $loadBehavior) {
                    Text("exercise.load_behavior.resistance".localized).tag(ExerciseLoadBehavior.resistance)
                    Text("exercise.load_behavior.assistance".localized).tag(ExerciseLoadBehavior.counterweightAssistance)
                }
                .pickerStyle(.segmented)
                Text(
                    loadBehavior.isCounterweightAssistance
                        ? "exercise.load_behavior.assistance.detail".localized
                        : "exercise.load_behavior.resistance.detail".localized
                )
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.45))
                .padding(.top, 8)
                .padding(.bottom, 22)

                // Equipment
                formLabel("exercises.equipment_type".localized)
                HStack(spacing: 8) {
                    ForEach(EquipmentType.allCases, id: \.self) { type in
                        equipmentTile(type)
                    }
                }
                .padding(.bottom, 22)

                // Live preview
                if canSave {
                    formLabel("add_exercise.preview".localized)
                    previewRow
                }

                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 18)
            .padding(.top, presentationMode == .navigation ? 12 : 4)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func formLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .kerning(0.7)
            .foregroundStyle(Color.white.opacity(0.45))
            .padding(.bottom, 10)
    }

    private func equipmentTile(_ type: EquipmentType) -> some View {
        let isActive = equipmentType == type
        return Button {
            HapticManager.shared.selection()
            equipmentType = type
        } label: {
            VStack(spacing: 7) {
                Image(systemName: type.icon)
                    .font(.system(size: 20, weight: .medium))
                Text(type.displayName)
                    .font(.system(size: 12, weight: isActive ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isActive ? DesignSystem.Colors.tint : Color.white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isActive ? DesignSystem.Colors.tint.opacity(0.14) : Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isActive ? DesignSystem.Colors.tint.opacity(0.45) : Color.white.opacity(0.06),
                        lineWidth: 1.5
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var previewRow: some View {
        HStack(spacing: 12) {
            ExerciseAvatarView(muscleGroups: muscleGroups, equipmentType: equipmentType)

            VStack(alignment: .leading, spacing: 3) {
                Text(exerciseName.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                EquipmentTagView(equipmentType: equipmentType)
            }

            Spacer(minLength: 8)

            if let primary = muscleGroups.first {
                MuscleChipView(muscleGroup: primary, small: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Actions

    private func toggleMuscleGroup(_ muscleGroup: String) {
        withAnimation(.easeOut(duration: 0.15)) {
            if let index = muscleGroups.firstIndex(of: muscleGroup) {
                muscleGroups.remove(at: index)
            } else {
                muscleGroups.append(muscleGroup)
            }
        }
    }

    private func saveExercise() {
        let trimmedName = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let exercise = exerciseToEdit {
            exercise.name = trimmedName
            exercise.muscleGroups = muscleGroups
            exercise.equipmentType = equipmentType
            exercise.loadBehavior = loadBehavior
            viewModel.updateExercise(exercise)
        } else {
            let newExercise = viewModel.addExercise(
                name: trimmedName,
                muscleGroups: muscleGroups,
                equipmentType: equipmentType,
                loadBehavior: loadBehavior
            )
            if let newExercise = newExercise {
                onExerciseCreated?(newExercise)
            }
        }

        dismiss()
    }
}

#Preview {
    Text("AddExerciseView Preview")
}
