import SwiftUI

/// Abstraction over ExerciseSet (pending, not yet persisted) and
/// AlternativeExerciseSet (persisted) so one inline editor serves both.
// NOTE: deliberately does NOT inherit Identifiable — @Model types already get
// Identifiable via PersistentModel, and re-stating it in a retroactive
// conformance emits a duplicate conformance descriptor (linker error).
protocol AlternativeEditableSet: AnyObject {
    var id: UUID { get }
    var reps: Int { get set }
    var weight: Double { get set }
    var restTime: TimeInterval { get set }
    var order: Int { get set }
}

extension ExerciseSet: AlternativeEditableSet {}
extension AlternativeExerciseSet: AlternativeEditableSet {}

/// Inline set editor for an alternative exercise: expandable set rows with
/// reps/weight steppers, apply-to-all banner, add/remove set, and a shared
/// rest timer. Rendered in place (inside a form section or an expanded routine
/// card) instead of on a separate page.
struct AlternativeSetsInlineEditor<SetType: AlternativeEditableSet>: View {
    let sets: [SetType]
    /// Appends a new set and returns it so it can be expanded immediately.
    let onAddSet: () -> SetType
    let onRemoveSet: (SetType) -> Void
    /// Persistence hook, called after a set's values changed (no-op for pending sets).
    let onSetChanged: (SetType) -> Void

    @State private var expandedSetId: UUID?
    @State private var editingReps = 10
    @State private var editingWeight = 0.0
    @State private var initialReps = 10
    @State private var initialWeight = 0.0
    @State private var bannerDismissed = false
    @State private var restTimerExpanded = false

    private var sortedSets: [SetType] {
        sets.sorted { $0.order < $1.order }
    }

    private var hasChanges: Bool {
        editingReps != initialReps || editingWeight != initialWeight
    }

    private var restTime: TimeInterval {
        sortedSets.first?.restTime ?? 0
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(sortedSets.enumerated()), id: \.element.id) { index, set in
                setRow(set: set, index: index)
            }

            // Add Set
            Button {
                saveCurrentEditingSet()
                let newSet = onAddSet()
                withAnimation(DesignSystem.Animation.spring) {
                    expand(newSet)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("exercise.add_set".localized)
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundStyle(DesignSystem.Colors.tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(DesignSystem.Colors.input)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            // Rest timer applies to all sets of this alternative
            RestTimerConfigView(
                restTime: Binding(
                    get: { restTime },
                    set: { newValue in
                        for set in sets {
                            set.restTime = newValue
                        }
                        if let first = sortedSets.first {
                            onSetChanged(first)
                        }
                    }
                ),
                isExpanded: $restTimerExpanded,
                showToggle: true
            )
        }
    }

    @ViewBuilder
    private func setRow(set: SetType, index: Int) -> some View {
        let isExpanded = expandedSetId == set.id
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if sortedSets.count > 1 {
                    Button {
                        if expandedSetId == set.id {
                            expandedSetId = nil
                        }
                        withAnimation(DesignSystem.Animation.spring) {
                            onRemoveSet(set)
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, .red)
                            .symbolRenderingMode(.palette)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("set.delete_accessibility".localized(index + 1))
                }

                Button {
                    withAnimation(DesignSystem.Animation.spring) {
                        if isExpanded {
                            saveCurrentEditingSet()
                            expandedSetId = nil
                        } else {
                            saveCurrentEditingSet()
                            expand(set)
                        }
                    }
                } label: {
                    HStack {
                        Text("set.number".localized(index + 1))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("configure_exercise.set_detail".localized(set.reps, set.weight))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 6)

            if isExpanded {
                VStack(spacing: 12) {
                    if sortedSets.count > 1 && hasChanges && !bannerDismissed {
                        ApplyToAllBanner(
                            setCount: sortedSets.count,
                            onApply: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    for s in sortedSets {
                                        s.reps = editingReps
                                        s.weight = editingWeight
                                        onSetChanged(s)
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
                        title: "set.reps_label".localized,
                        value: $editingReps,
                        range: 1...100
                    ) { _ in
                        // Guard: only process updates for the currently expanded set
                        guard expandedSetId == set.id else { return }
                        set.reps = editingReps
                        onSetChanged(set)
                    }

                    WeightInput(
                        title: "set.weight_label".localized,
                        weight: $editingWeight
                    ) { _ in
                        // Guard: only process updates for the currently expanded set
                        guard expandedSetId == set.id else { return }
                        set.weight = editingWeight
                        onSetChanged(set)
                    }
                }
                .padding(.bottom, 8)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                ))
            }
        }
    }

    private func expand(_ set: SetType) {
        expandedSetId = set.id
        editingReps = set.reps
        editingWeight = set.weight
        initialReps = set.reps
        initialWeight = set.weight
        bannerDismissed = false
    }

    private func saveCurrentEditingSet() {
        guard let currentId = expandedSetId,
              let currentSet = sets.first(where: { $0.id == currentId }) else { return }
        if currentSet.reps != editingReps || currentSet.weight != editingWeight {
            currentSet.reps = editingReps
            currentSet.weight = editingWeight
            onSetChanged(currentSet)
        }
    }
}
