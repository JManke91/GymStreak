//
//  ExerciseVisuals.swift
//  GymStreak
//
//  Shared visual primitives of the Routinen & Übungen redesign:
//  muscle-colored exercise avatar, muscle chip, equipment tag and meta chip.
//  Color = muscle group, glyph = equipment (deliberately not name initials —
//  those duplicate the adjacent label).
//

import SwiftUI

/// Muscle-colored tile with the exercise's equipment icon.
struct ExerciseAvatarView: View {
    let muscleGroups: [String]
    let equipmentType: EquipmentType
    var size: CGFloat = 42
    var radius: CGFloat = 12

    private var color: Color { MuscleGroups.color(for: muscleGroups) }

    var body: some View {
        Image(systemName: equipmentType.icon)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.16))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(color.opacity(0.28), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Pill chip showing a localized muscle-group name in its category color.
struct MuscleChipView: View {
    let muscleGroup: String
    var small: Bool = false

    private var color: Color { MuscleGroups.color(for: muscleGroup) }

    var body: some View {
        Text(MuscleGroups.displayName(for: muscleGroup))
            .font(.system(size: small ? 10 : 11, weight: .semibold))
            .kerning(0.3)
            .foregroundStyle(color)
            .padding(.horizontal, small ? 8 : 10)
            .padding(.vertical, small ? 2.5 : 3.5)
            .background(color.opacity(0.13))
            .clipShape(Capsule())
            .lineLimit(1)
            .fixedSize()
    }
}

/// Small equipment icon + label, muted by default.
struct EquipmentTagView: View {
    let equipmentType: EquipmentType
    var muted: Bool = true

    private var color: Color { muted ? Color.white.opacity(0.45) : .white }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: equipmentType.icon)
                .font(.system(size: 10, weight: .medium))
            Text(equipmentType.displayName)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(color)
        .lineLimit(1)
    }
}

/// Rounded meta chip (icon + text) used in detail headers and exercise cards.
struct MetaChipView: View {
    let icon: String
    let text: String
    var color: Color = Color.white.opacity(0.65)

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 11.5, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .lineLimit(1)
        .fixedSize()
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ExerciseAvatarView(muscleGroups: ["Chest"], equipmentType: .barbell)
                ExerciseAvatarView(muscleGroups: ["Biceps"], equipmentType: .dumbbell)
                ExerciseAvatarView(muscleGroups: ["Quadriceps"], equipmentType: .machine, size: 58, radius: 18)
            }
            HStack(spacing: 8) {
                MuscleChipView(muscleGroup: "Chest")
                MuscleChipView(muscleGroup: "Shoulders", small: true)
                MuscleChipView(muscleGroup: "Lats")
            }
            HStack(spacing: 12) {
                EquipmentTagView(equipmentType: .barbell)
                MetaChipView(icon: "timer", text: "Pause 2:30 min", color: DesignSystem.Colors.tint)
                MetaChipView(icon: "target", text: "Ziel 6 Wdh.")
            }
        }
    }
}
