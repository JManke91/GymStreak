//
//  ExercisePickerRowView.swift
//  GymStreak
//
//  The one library-exercise row every picker in the app uses: the avatar, the name, its
//  primary muscle group and equipment tag, and a trailing action symbol.
//
//  Extracted so the AI routine draft's "which exercise did you mean?" picker
//  (docs/ai-coach-routine-drafting.md) reads exactly like the add-to-routine picker it
//  sits beside, instead of carrying a second copy of the same 30 lines of styling.
//

import SwiftUI

struct ExercisePickerRowView: View {

    let exercise: Exercise
    /// What the row promises tapping it does — a plus where it adds the exercise to
    /// something, a checkmark where it picks one.
    var trailingSymbol: String = "plus"

    var body: some View {
        HStack(spacing: 12) {
            ExerciseAvatarView(
                muscleGroups: exercise.muscleGroups,
                equipmentType: exercise.equipmentType,
                size: 38
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(MuscleGroups.displayName(for: exercise.primaryMuscleGroup))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.5))
                    EquipmentTagView(equipmentType: exercise.equipmentType)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: trailingSymbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
