//
//  ExerciseLibraryRowView.swift
//  GymStreak
//
//  Library row of the redesigned Übungen tab.
//

import SwiftUI

struct ExerciseLibraryRowView: View {
    let exercise: Exercise
    let usedInCount: Int

    var body: some View {
        HStack(spacing: 12) {
            ExerciseAvatarView(
                muscleGroups: exercise.muscleGroups,
                equipmentType: exercise.equipmentType
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .kerning(-0.2)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    EquipmentTagView(equipmentType: exercise.equipmentType)
                    if usedInCount > 0 {
                        Circle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 2, height: 2)
                        Text(usedInCount == 1
                             ? "exercises.used_in.one".localized
                             : "exercises.used_in.many".localized(usedInCount))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                }
            }

            Spacer(minLength: 8)

            MuscleChipView(muscleGroup: exercise.primaryMuscleGroup, small: true)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.3))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

