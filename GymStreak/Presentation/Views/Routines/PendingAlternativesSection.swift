import SwiftUI

/// Optional "Alternative Exercises" section for the exercise configure screens.
/// Holds not-yet-persisted alternatives with their own editable set schemes;
/// tapping a row expands an inline set editor (reps, weight, rest) in place.
struct PendingAlternativesSection: View {
    let primaryExercise: Exercise
    @Binding var alternatives: [PendingAlternative]
    @Binding var showingPicker: Bool
    @Binding var expandedAlternativeId: UUID?
    /// Shared "a set value is being typed" flag driving the screen's Done bar.
    var valueFocus: FocusState<Bool>.Binding

    var body: some View {
        Section {
            ForEach(alternatives) { alternative in
                let isExpanded = expandedAlternativeId == alternative.id
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(DesignSystem.Animation.spring) {
                            expandedAlternativeId = isExpanded ? nil : alternative.id
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Button {
                                if isExpanded { expandedAlternativeId = nil }
                                withAnimation(DesignSystem.Animation.spring) {
                                    alternatives.removeAll { $0.id == alternative.id }
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white, .red)
                                    .symbolRenderingMode(.palette)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("alternatives.remove_accessibility".localized(alternative.exercise.name))

                            Image(systemName: alternative.exercise.equipmentType.icon)
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(alternative.exercise.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text("routine.sets_count".localized(alternative.sets.count))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isExpanded {
                        RoutineSetsEditor(
                            sets: alternative.sets,
                            valueFocus: valueFocus,
                            onAddSet: {
                                let last = alternative.sets.max(by: { $0.order < $1.order })
                                let newSet = ExerciseSet(
                                    reps: last?.reps ?? 10,
                                    weight: last?.weight ?? 0.0,
                                    restTime: last?.restTime ?? 0,
                                    order: (last?.order ?? -1) + 1
                                )
                                alternative.sets.append(newSet)
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
                        .padding(.top, 6)
                        .padding(.bottom, 4)
                    }
                }
            }

            Button {
                showingPicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("alternatives.add".localized)
                }
                .foregroundColor(.accentColor)
            }
        } header: {
            Text("configure_exercise.alternatives.header".localized)
        } footer: {
            Text("configure_exercise.alternatives.explanation".localized)
        }
    }
}
