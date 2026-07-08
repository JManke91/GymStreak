//
//  AlternativeFocusedEditor.swift
//  GymStreak
//
//  The full editor for a single alternative variant, shown in an expanded
//  exercise card IN PLACE OF the primary's configuration when that alternative is
//  focused (via the ExerciseVariantSwitcher pill or the alternatives browse
//  sheet). Contains the alternative's own rep-range goal, its independent set
//  scheme (AlternativeSetsInlineEditor, which carries its own rest timer) and a
//  confirm-gated removal.
//
//  Replaces the former AlternativeInlineSection, which stacked every alternative's
//  editor below the primary in one very tall cell — the card now shows exactly one
//  variant at a time (see docs/alternative-exercises.md).
//

import SwiftUI

struct AlternativeFocusedEditor: View {
    let alternative: RoutineExerciseAlternative
    @ObservedObject var viewModel: RoutinesViewModel
    /// Called after the alternative is removed so the card can refocus the primary.
    let onRemoved: () -> Void

    @State private var repRangeExpanded = false
    @State private var confirmingRemoval = false

    var body: some View {
        VStack(spacing: 12) {
            // Rep-range goal — same control as the primary, targeting this
            // alternative's own independent goal.
            RepRangeConfigView(
                targetRepMin: Binding(
                    get: { alternative.targetRepMin },
                    set: { alternative.targetRepMin = $0 }
                ),
                targetRepMax: Binding(
                    get: { alternative.targetRepMax },
                    set: { alternative.targetRepMax = $0 }
                ),
                isExpanded: $repRangeExpanded,
                onRepRangeChange: { min, max in
                    viewModel.updateRepRange(for: alternative, min: min, max: max)
                }
            )

            AlternativeSetsInlineEditor(
                sets: alternative.setsList,
                onAddSet: { viewModel.addSet(to: alternative) },
                onRemoveSet: { viewModel.removeSet($0, from: alternative) },
                onSetChanged: { viewModel.updateSet($0) },
                targetRepMin: alternative.targetRepMin,
                targetRepMax: alternative.targetRepMax
            )

            Button(role: .destructive) {
                confirmingRemoval = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.subheadline)
                    Text("alternatives.remove".localized)
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("alternatives.remove_accessibility".localized(alternative.exercise?.name ?? ""))
        }
        .alert("alternatives.remove.title".localized, isPresented: $confirmingRemoval) {
            Button("alternatives.remove.confirm".localized, role: .destructive) {
                if let parent = alternative.routineExercise {
                    withAnimation(DesignSystem.Animation.spring) {
                        viewModel.removeAlternative(alternative, from: parent)
                    }
                }
                onRemoved()
            }
            Button("action.cancel".localized, role: .cancel) {}
        } message: {
            Text("alternatives.remove.message".localized)
        }
    }
}
