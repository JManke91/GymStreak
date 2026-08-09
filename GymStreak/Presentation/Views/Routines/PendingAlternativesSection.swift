import SwiftUI

/// The "Alternativübungen" block of `ConfigureExerciseSetsView`: not-yet-persisted
/// alternatives with their own editable set schemes. Tapping a row expands the
/// shared set editor in place — the same one the primary exercise and the routine
/// detail screen use.
///
/// Renders plain content (no `Section`); the caller supplies the card chrome.
struct PendingAlternativesSection: View {
    @Binding var alternatives: [PendingAlternative]
    @Binding var showingPicker: Bool
    @Binding var expandedAlternativeId: UUID?
    /// Shared "a set value is being typed" flag driving the screen's Done bar.
    var valueFocus: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("configure_exercise.alternatives.explanation".localized)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
                .padding(.bottom, 2)

            ForEach(alternatives) { alternative in
                alternativeCell(alternative)
            }

            DashedCreateButton(title: "alternatives.add".localized, compact: true) {
                showingPicker = true
            }
        }
    }

    @ViewBuilder
    private func alternativeCell(_ alternative: PendingAlternative) -> some View {
        let isExpanded = expandedAlternativeId == alternative.id

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    HapticManager.shared.light()
                    if isExpanded { expandedAlternativeId = nil }
                    withAnimation(DesignSystem.Animation.spring) {
                        alternatives.removeAll { $0.id == alternative.id }
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 16))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, DesignSystem.Colors.destructive)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("alternatives.remove_accessibility".localized(alternative.exercise.name))

                Button {
                    HapticManager.shared.light()
                    withAnimation(DesignSystem.Animation.spring) {
                        expandedAlternativeId = isExpanded ? nil : alternative.id
                    }
                } label: {
                    HStack(spacing: 10) {
                        ExerciseAvatarView(
                            muscleGroups: alternative.exercise.muscleGroups,
                            equipmentType: alternative.exercise.equipmentType,
                            size: 30,
                            radius: 9
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(alternative.exercise.name)
                                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Text(SetSummaryFormatting.text(
                                reps: alternative.sets.map(\.reps),
                                weights: alternative.sets.map(\.weight)
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
                .accessibilityLabel("alternatives.view_accessibility".localized(alternative.exercise.name))
            }

            if isExpanded {
                RoutineSetsEditor(
                    sets: alternative.sets,
                    valueFocus: valueFocus,
                    onAddSet: {
                        let last = alternative.sets.max(by: { $0.order < $1.order })
                        alternative.sets.append(
                            ExerciseSet(
                                reps: last?.reps ?? 10,
                                weight: last?.weight ?? 0.0,
                                restTime: last?.restTime ?? 0,
                                order: (last?.order ?? -1) + 1
                            )
                        )
                    },
                    onRemoveSet: { set in
                        alternative.sets.removeAll { $0.id == set.id }
                        for (order, remaining) in alternative.sets.sorted(by: { $0.order < $1.order }).enumerated() {
                            remaining.order = order
                        }
                    },
                    onSetChanged: { _ in },
                    onApplyToAll: { source, field in
                        for set in alternative.sets {
                            switch field {
                            case .reps: set.reps = source.reps
                            case .weight: set.weight = source.weight
                            }
                        }
                    }
                )
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
}
