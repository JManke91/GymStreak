//
//  RoutineSetsEditor.swift
//  GymStreak
//
//  The always-editable set list of an exercise card (redesign v2): one row per
//  set (RoutineSetStepperRow) with a remove button, an index badge and
//  reps/weight steppers whose value can also be typed. Replaces the former
//  tap-to-expand RoutineSetRowView and AlternativeSetsInlineEditor — the primary
//  exercise and its alternatives now share one editor.
//

import SwiftUI

/// Abstraction over `ExerciseSet` (also used unpersisted in the picker flow) and
/// `AlternativeExerciseSet` so one editor serves both.
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

// MARK: - Set list

/// The "SÄTZE" block of an exercise card: rows, the apply-to-all banner for the
/// most recently edited row, and the inline add-set button.
struct RoutineSetsEditor<SetType: AlternativeEditableSet>: View {
    let sets: [SetType]
    var targetRepMin: Int? = nil
    var targetRepMax: Int? = nil
    var valueFocus: FocusState<Bool>.Binding
    /// Appends a new set (seeded from the last one).
    let onAddSet: () -> Void
    let onRemoveSet: (SetType) -> Void
    /// Persistence hook, called after a set's values changed.
    let onSetChanged: (SetType) -> Void
    /// Copies the given set's reps + weight onto every set of this exercise.
    let onApplyToAll: (SetType, ApplyToAllType) -> Void

    /// Which row was edited last — the apply-to-all banner is offered under it
    /// until the user applies or dismisses it.
    @State private var recentlyEditedSetId: UUID?
    @State private var recentlyEditedField: ApplyToAllType?

    var body: some View {
        // Sort once per body pass — `sets` is a model collection.
        let sortedSets = sets.sorted { $0.order < $1.order }
        return VStack(spacing: 6) {
            ForEach(Array(sortedSets.enumerated()), id: \.element.id) { index, set in
                VStack(spacing: 6) {
                    RoutineSetStepperRow(
                        index: index,
                        reps: set.reps,
                        weight: set.weight,
                        targetRepMin: targetRepMin,
                        targetRepMax: targetRepMax,
                        canRemove: sortedSets.count > 1,
                        valueFocus: valueFocus,
                        onRepsChange: { newValue in
                            guard newValue != set.reps else { return }
                            set.reps = newValue
                            onSetChanged(set)
                            noteEdit(of: set, field: .reps)
                        },
                        onWeightChange: { newValue in
                            guard newValue != set.weight else { return }
                            set.weight = newValue
                            onSetChanged(set)
                            noteEdit(of: set, field: .weight)
                        },
                        onRemove: {
                            if recentlyEditedSetId == set.id { clearBanner() }
                            withAnimation(DesignSystem.Animation.spring) {
                                onRemoveSet(set)
                            }
                        }
                    )

                    if sortedSets.count > 1,
                       recentlyEditedSetId == set.id,
                       let field = recentlyEditedField {
                        ApplyToAllBanner(
                            type: field,
                            setCount: sortedSets.count,
                            onApply: {
                                withAnimation(DesignSystem.Animation.spring) {
                                    onApplyToAll(set, field)
                                    clearBanner()
                                }
                            },
                            onDismiss: {
                                withAnimation(DesignSystem.Animation.spring) { clearBanner() }
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            DashedCreateButton(title: "exercise.add_set".localized, tinted: true) {
                clearBanner()
                withAnimation(DesignSystem.Animation.spring) {
                    onAddSet()
                }
            }
        }
    }

    private func noteEdit(of set: SetType, field: ApplyToAllType) {
        guard sets.count > 1 else { return }
        withAnimation(DesignSystem.Animation.spring) {
            recentlyEditedSetId = set.id
            recentlyEditedField = field
        }
    }

    private func clearBanner() {
        recentlyEditedSetId = nil
        recentlyEditedField = nil
    }
}
