import SwiftUI

struct ExerciseDetailView: View {
    let exercise: Exercise
    @ObservedObject var viewModel: ExercisesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false

    private var muscleColor: Color { MuscleGroups.color(for: exercise.muscleGroups) }

    /// Routines using this exercise (primary uses first), derived by the ViewModel.
    private var usages: [(routine: Routine, routineExercise: RoutineExercise?)] {
        viewModel.usages(for: exercise)
    }

    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    topBar
                    hero
                    infoCard
                    usedInSection
                    Color.clear.frame(height: 60)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingEdit) {
            AddExerciseView(viewModel: viewModel, exerciseToEdit: exercise)
        }
        .alert("exercises.delete.confirmation.title".localized, isPresented: $viewModel.showingDeleteConfirmation) {
            Button("common.cancel".localized, role: .cancel) {
                viewModel.cancelDeleteExercise()
            }
            Button("exercises.delete.confirm".localized, role: .destructive) {
                viewModel.confirmDeleteExercise()
                dismiss()
            }
        } message: {
            let exerciseName = viewModel.exerciseToDelete?.name ?? ""
            if viewModel.routinesUsingExercise.isEmpty {
                Text(String(format: "exercises.delete.confirmation.message_standalone".localized, exerciseName))
            } else {
                let routineNames = viewModel.routinesUsingExercise.map(\.name).joined(separator: ", ")
                Text(String(format: "exercises.delete.confirmation.message".localized, exerciseName, routineNames))
            }
        }
        .onChange(of: viewModel.exercises) { _, exercises in
            // Dismiss if the current exercise was deleted
            if !exercises.contains(where: { $0.id == exercise.id }) {
                dismiss()
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                HapticManager.shared.light()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("action.back".localized)

            Spacer()

            Menu {
                Button {
                    showingEdit = true
                } label: {
                    Label("exercise.edit".localized, systemImage: "pencil")
                }
                Button(role: .destructive) {
                    viewModel.requestDeleteExercise(exercise)
                } label: {
                    Label("exercise.delete".localized, systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(spacing: 14) {
            ExerciseAvatarView(
                muscleGroups: exercise.muscleGroups,
                equipmentType: exercise.equipmentType,
                size: 58,
                radius: 18
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(MuscleGroups.displayName(for: exercise.primaryMuscleGroup).uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .kerning(0.6)
                    .foregroundStyle(muscleColor)
                Text(exercise.name)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .kerning(-0.6)
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Info card

    private var infoCard: some View {
        VStack(spacing: 0) {
            infoRow(label: "exercises.muscle_groups".localized) {
                HStack(spacing: 5) {
                    ForEach(exercise.muscleGroups, id: \.self) { muscle in
                        MuscleChipView(muscleGroup: muscle)
                    }
                }
            }

            Divider().overlay(Color.white.opacity(0.05))

            infoRow(label: "exercises.equipment_type".localized) {
                HStack(spacing: 6) {
                    Image(systemName: exercise.equipmentType.icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                    Text(exercise.equipmentType.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .background(Color.white.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func infoRow(label: String, @ViewBuilder value: () -> some View) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
            Spacer(minLength: 12)
            ScrollView(.horizontal, showsIndicators: false) {
                value()
            }
            .frame(maxWidth: 240)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Used in

    private var usedInSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("exercise.detail.used_in".localized)
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text(usages.count == 1
                     ? "exercises.used_in.one".localized
                     : "exercises.used_in.many".localized(usages.count))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)

            if usages.isEmpty {
                Text("exercise.detail.not_used".localized)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                            .foregroundStyle(Color.white.opacity(0.12))
                    )
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 8) {
                    ForEach(usages, id: \.routine.id) { usage in
                        usageRow(usage.routine, routineExercise: usage.routineExercise)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func usageRow(_ routine: Routine, routineExercise: RoutineExercise?) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(routine.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(setSummary(for: routineExercise))
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.5))
            }

            Spacer()

            if routineExercise == nil {
                MetaChipView(icon: "arrow.triangle.2.circlepath", text: "exercise.detail.alternative".localized)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func setSummary(for routineExercise: RoutineExercise?) -> String {
        guard let routineExercise else {
            return "exercise.detail.as_alternative".localized
        }
        let sets = routineExercise.setsList.sorted { $0.order < $1.order }
        if let scheme = RoutineMetricsService.uniformSetScheme(
            reps: sets.map(\.reps),
            weights: sets.map(\.weight)
        ) {
            return String(
                format: "exercise.detail.set_scheme".localized,
                sets.count, scheme.reps, scheme.weight
            )
        }
        return "routine.sets_count".localized(sets.count)
    }
}

#Preview {
    Text("ExerciseDetailView Preview")
}
