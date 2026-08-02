//
//  WorkoutExerciseCollapsedRow.swift
//  GymStreak
//
//  An exercise you are not working on right now. Only one exercise is expanded
//  at a time in the active workout, so everything else shrinks to this row —
//  enough to recognise the exercise and see how far it got, and tappable to
//  make it the open one. Its companion is `WorkoutExerciseCardView`.
//

import SwiftUI

/// Everything you are not working on right now.
struct WorkoutExerciseCollapsedRow: View {
    let display: WorkoutExerciseDisplay
    let supersetBadge: (position: Int, total: Int, color: Color)?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                ExerciseAvatarView(
                    muscleGroups: display.muscleGroups,
                    equipmentType: display.equipmentType,
                    size: 38,
                    radius: 11
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(display.name)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(display.isComplete ? Color.white.opacity(0.5) : .white)
                        .lineLimit(1)

                    Text(collapsedMeta)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if let supersetBadge {
                    SupersetBadge(
                        position: supersetBadge.position,
                        total: supersetBadge.total,
                        color: supersetBadge.color
                    )
                }

                if display.isComplete {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                        Text("\(display.completedSets)/\(display.totalSets)")
                            .font(.system(size: 12, weight: .bold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(DesignSystem.Colors.tint)
                } else {
                    Text("\(display.completedSets)/\(display.totalSets)")
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.35))
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("workout.exercise.open_hint".localized)
    }

    private var collapsedMeta: String {
        let sets = "workout.exercise.set_count".localized(display.totalSets)
        // Bodyweight exercises log 0 kg; "0 kg" reads as missing data, so the
        // weight is simply left off.
        guard display.leadWeight > 0 else { return sets }
        let weight = display.isAssistance
            ? "exercise.assistance.value".localized(WorkoutValueFormatting.weight(display.leadWeight))
            : "set.weight_compact".localized(WorkoutValueFormatting.weight(display.leadWeight))
        return "\(sets) · \(weight)"
    }
}
