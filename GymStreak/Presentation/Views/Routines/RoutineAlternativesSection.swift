//
//  RoutineAlternativesSection.swift
//  GymStreak
//
//  The "Alternativen" block inside an expanded exercise card (redesign v2):
//  a flat list of the slot's alternatives, each row expandable in place into its
//  own parameter chips and set editor. Replaces the variant-switcher pills +
//  AlternativeFocusedEditor + AlternativesBrowseView of v1 — an alternative is
//  now edited without swapping out the primary's body.
//

import SwiftUI

struct RoutineAlternativesSection: View {
    let routineExercise: RoutineExercise
    @ObservedObject var viewModel: RoutinesViewModel
    /// The alternative whose editor is open (nil = list only).
    @Binding var expandedAlternativeId: UUID?
    var valueFocus: FocusState<Bool>.Binding
    let onAddAlternative: () -> Void

    /// Which parameter editor of the expanded alternative is open.
    @State private var openParameter: ExerciseCardParameter?
    @State private var alternativePendingRemoval: RoutineExerciseAlternative?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SetsSectionLabel(text: "alternatives.section_title".localized, icon: "arrow.triangle.2.circlepath")

            ForEach(routineExercise.alternativesList) { alternative in
                alternativeCell(alternative)
            }

            DashedCreateButton(title: "alternatives.add".localized, compact: true) {
                onAddAlternative()
            }
        }
        .alert("alternatives.remove.title".localized, isPresented: removalAlertBinding) {
            Button("alternatives.remove.confirm".localized, role: .destructive) {
                if let alternative = alternativePendingRemoval {
                    if expandedAlternativeId == alternative.id { expandedAlternativeId = nil }
                    withAnimation(DesignSystem.Animation.spring) {
                        viewModel.removeAlternative(alternative, from: routineExercise)
                    }
                }
                alternativePendingRemoval = nil
            }
            Button("action.cancel".localized, role: .cancel) { alternativePendingRemoval = nil }
        } message: {
            Text("alternatives.remove.message".localized)
        }
    }

    private var removalAlertBinding: Binding<Bool> {
        Binding(
            get: { alternativePendingRemoval != nil },
            set: { if !$0 { alternativePendingRemoval = nil } }
        )
    }

    @ViewBuilder
    private func alternativeCell(_ alternative: RoutineExerciseAlternative) -> some View {
        let isExpanded = expandedAlternativeId == alternative.id

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    HapticManager.shared.light()
                    alternativePendingRemoval = alternative
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 16))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, DesignSystem.Colors.destructive)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("alternatives.remove_accessibility".localized(alternative.exercise?.name ?? ""))

                Button {
                    HapticManager.shared.light()
                    withAnimation(DesignSystem.Animation.spring) {
                        openParameter = nil
                        expandedAlternativeId = isExpanded ? nil : alternative.id
                    }
                } label: {
                    HStack(spacing: 10) {
                        if let exercise = alternative.exercise {
                            ExerciseAvatarView(
                                muscleGroups: exercise.muscleGroups,
                                equipmentType: exercise.equipmentType,
                                size: 30,
                                radius: 9
                            )
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(alternative.exercise?.name ?? "")
                                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Text(SetSummaryFormatting.text(
                                reps: alternative.setsList.map(\.reps),
                                weights: alternative.setsList.map(\.weight)
                            ))
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(Color.white.opacity(0.45))
                            .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.3))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("alternatives.view_accessibility".localized(alternative.exercise?.name ?? ""))
            }

            if isExpanded {
                alternativeEditor(alternative)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// The expanded alternative mirrors the primary's layout: parameter chips
    /// with their inline editors, then the shared set editor.
    @ViewBuilder
    private func alternativeEditor(_ alternative: RoutineExerciseAlternative) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ExerciseParameterChips(
                restTime: alternative.setsList.first?.restTime ?? 0,
                targetRepMin: alternative.targetRepMin,
                targetRepMax: alternative.targetRepMax,
                openParameter: $openParameter
            )

            if let parameter = openParameter {
                switch parameter {
                case .rest:
                    RestTimeInlineEditor(restTime: alternative.setsList.first?.restTime ?? 0) { newValue in
                        viewModel.updateRestTime(newValue, for: alternative)
                    }
                case .repRange:
                    RepRangeInlineEditor(
                        targetRepMin: alternative.targetRepMin,
                        targetRepMax: alternative.targetRepMax
                    ) { min, max in
                        viewModel.updateRepRange(for: alternative, min: min, max: max)
                    }
                }
            }

            SetsSectionLabel(text: "routine.section.sets".localized)

            RoutineSetsEditor(
                sets: alternative.setsList,
                targetRepMin: alternative.targetRepMin,
                targetRepMax: alternative.targetRepMax,
                valueFocus: valueFocus,
                onAddSet: { _ = viewModel.addSet(to: alternative) },
                onRemoveSet: { viewModel.removeSet($0, from: alternative) },
                onSetChanged: { viewModel.updateSet($0) },
                onApplyToAll: { source, field in
                    viewModel.applyToAllSets(from: source, field: field, in: alternative)
                }
            )
        }
    }
}
