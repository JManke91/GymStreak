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
    /// Optional rep-range goal of the owning alternative — drives the per-set
    /// progress badge + reps color, mirroring RoutineSetRowView. nil = no goal.
    var targetRepMin: Int? = nil
    var targetRepMax: Int? = nil

    @State private var expandedSetId: UUID?
    @State private var editingReps = 10
    @State private var editingWeight = 0.0
    @State private var initialReps = 10
    @State private var initialWeight = 0.0
    @State private var bannerDismissed = false
    @State private var restTimerExpanded = false
    @State private var pendingDeleteSetId: UUID?

    private var sortedSets: [SetType] {
        sets.sorted { $0.order < $1.order }
    }

    private var hasChanges: Bool {
        editingReps != initialReps || editingWeight != initialWeight
    }

    private var restTime: TimeInterval {
        sortedSets.first?.restTime ?? 0
    }

    private func repRangeColor(for reps: Int) -> Color {
        guard let min = targetRepMin, let max = targetRepMax else { return .white }
        if reps >= max {
            return .orange
        } else if reps >= min {
            return DesignSystem.Colors.tint
        } else {
            return Color.white.opacity(0.6)
        }
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
        .alert("set.delete.title".localized, isPresented: deleteAlertBinding) {
            Button("set.delete.confirm".localized, role: .destructive) {
                if let id = pendingDeleteSetId, let set = sets.first(where: { $0.id == id }) {
                    if expandedSetId == id { expandedSetId = nil }
                    withAnimation(DesignSystem.Animation.spring) {
                        onRemoveSet(set)
                    }
                }
                pendingDeleteSetId = nil
            }
            Button("action.cancel".localized, role: .cancel) { pendingDeleteSetId = nil }
        } message: {
            Text("set.delete.message".localized)
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteSetId != nil },
            set: { if !$0 { pendingDeleteSetId = nil } }
        )
    }

    // Mirrors RoutineSetRowView so an alternative's sets read and behave
    // identically to the primary exercise's sets: numbered badge, "reps × weight",
    // a chevron.down that expands the row in place, and a delete action that lives
    // INSIDE the expanded cell (not an always-visible minus).
    @ViewBuilder
    private func setRow(set: SetType, index: Int) -> some View {
        let isExpanded = expandedSetId == set.id
        VStack(alignment: .leading, spacing: 0) {
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
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.system(size: 11.5, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(DesignSystem.Colors.tint)
                        .frame(width: 24, height: 24)
                        .background(DesignSystem.Colors.tint.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("set.reps".localized(set.reps))
                            .foregroundStyle(repRangeColor(for: set.reps))
                        Text("×")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.35))
                        Text("set.weight".localized(set.weight))
                            .foregroundStyle(.white)
                    }
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .monospacedDigit()

                    // Rep-range progress badge (mirrors RoutineSetRowView)
                    if let max = targetRepMax {
                        Text("\(set.reps)/\(max)")
                            .font(.caption2.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(repRangeColor(for: set.reps))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(repRangeColor(for: set.reps).opacity(0.1), in: Capsule())
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(isExpanded ? .subheadline.weight(.bold) : .caption.weight(.semibold))
                        .foregroundStyle(isExpanded ? DesignSystem.Colors.tint : Color.white.opacity(0.35))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(DesignSystem.Animation.spring, value: isExpanded)
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("accessibility.set.label".localized(index + 1, set.reps, set.weight))

            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)

                VStack(spacing: 16) {
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

                    // Delete lives inside the expanded cell (matches RoutineSetRowView).
                    // Only offered when more than one set remains.
                    if sortedSets.count > 1 {
                        Button(role: .destructive) {
                            pendingDeleteSetId = set.id
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                    .font(.subheadline)
                                Text("set.delete".localized)
                                    .font(.subheadline.weight(.medium))
                            }
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("set.delete_accessibility".localized(index + 1))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isExpanded ? Color.white.opacity(0.06) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isExpanded ? DesignSystem.Colors.tint.opacity(0.3) : Color.clear, lineWidth: 1)
        )
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
