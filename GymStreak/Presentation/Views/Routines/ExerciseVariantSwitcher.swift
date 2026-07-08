//
//  ExerciseVariantSwitcher.swift
//  GymStreak
//
//  Horizontal variant selector shown at the top of an expanded exercise card:
//  the primary exercise plus each configured alternative as peer pills, and a
//  "+" pill to add another. Selecting a pill focuses that variant so the card
//  body renders ONLY that one exercise's configuration — a routine exercise is a
//  single "slot" the user configures one variant at a time (see
//  RoutineDetailView.normalSetContent and docs/alternative-exercises.md).
//

import SwiftUI

struct ExerciseVariantSwitcher: View {
    let routineExercise: RoutineExercise
    /// nil = the primary exercise is focused; otherwise the focused alternative's id.
    @Binding var focusedAlternativeId: UUID?
    let onAddAlternative: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterPillButton(
                    label: routineExercise.exercise?.name ?? "",
                    isActive: focusedAlternativeId == nil
                ) {
                    withAnimation(DesignSystem.Animation.spring) { focusedAlternativeId = nil }
                }

                ForEach(routineExercise.alternativesList) { alternative in
                    FilterPillButton(
                        label: alternative.exercise?.name ?? "",
                        isActive: focusedAlternativeId == alternative.id
                    ) {
                        withAnimation(DesignSystem.Animation.spring) { focusedAlternativeId = alternative.id }
                    }
                }

                addPill
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    private var addPill: some View {
        Button(action: onAddAlternative) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.tint)
                .frame(width: 34, height: 34)
                .overlay(
                    Circle().stroke(
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                    )
                    .foregroundStyle(DesignSystem.Colors.tint.opacity(0.4))
                )
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("alternatives.add".localized)
    }
}
