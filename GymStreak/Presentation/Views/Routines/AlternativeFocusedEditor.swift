//
//  AlternativeFocusedEditor.swift
//  GymStreak
//
//  The full editor for a single alternative variant, shown in an expanded
//  exercise card IN PLACE OF the primary's configuration when that alternative is
//  focused (via the ExerciseVariantSwitcher pill or the alternatives browse
//  sheet). Mirrors primarySetContent's layout exactly: rest timer, the
//  alternative's own rep-range goal, SETS label, its independent set scheme
//  (AlternativeSetsInlineEditor with showsRestTimer: false), and a
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
    @State private var restTimerExpanded = false
    @State private var confirmingRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Same layout order as the primary variant (primarySetContent in
            // RoutineDetailView): rest timer, rep-range goal, SETS label, set
            // rows, inline add-set — so switching variants never reshuffles UI.
            RestTimerConfigView(
                restTime: Binding(
                    get: { alternative.setsList.first?.restTime ?? 0 },
                    set: { newValue in
                        for set in alternative.setsList {
                            set.restTime = newValue
                        }
                        if let first = alternative.setsList.first {
                            viewModel.updateSet(first)
                        }
                    }
                ),
                isExpanded: $restTimerExpanded,
                showToggle: true
            )

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

            SetsSectionLabel(text: "routine.section.sets".localized)

            AlternativeSetsInlineEditor(
                sets: alternative.setsList,
                onAddSet: { viewModel.addSet(to: alternative) },
                onRemoveSet: { viewModel.removeSet($0, from: alternative) },
                onSetChanged: { viewModel.updateSet($0) },
                targetRepMin: alternative.targetRepMin,
                targetRepMax: alternative.targetRepMax,
                showsRestTimer: false
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
