//
//  WorkoutSetRowView.swift
//  GymStreak
//
//  One set of the exercise you are currently on, in the redesigned active
//  workout. Its whole point is that checking off and editing no longer share a
//  hit area: the left 62pt column is the completion zone over the full row
//  height, and to its right only the reps/weight chips react. The row itself is
//  not a button, so a mistap can no longer rewrite a value or expand anything.
//

import SwiftUI

struct WorkoutSetRowView: View {
    let display: WorkoutSetDisplay
    /// True for the first incomplete set of the exercise you are on.
    let isNext: Bool
    let onToggleCompleted: () -> Void
    let onEdit: (WorkoutSetField) -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    private var borderColor: Color {
        if display.isCompleted { return DesignSystem.Colors.tint.opacity(0.22) }
        if isNext { return DesignSystem.Colors.tint.opacity(0.38) }
        return Color.white.opacity(0.07)
    }

    private var backgroundColor: Color {
        if display.isCompleted { return DesignSystem.Colors.tint.opacity(0.07) }
        if isNext { return Color.white.opacity(0.05) }
        return Color.white.opacity(0.025)
    }

    private var numberColor: Color {
        if display.isCompleted { return DesignSystem.Colors.tint.opacity(0.7) }
        if isNext { return DesignSystem.Colors.tint }
        return Color.white.opacity(0.32)
    }

    /// Reps get the only value coloring: orange off-goal, tint once the goal's
    /// upper limit is reached (the cue that a weight increase is due).
    private var repsColor: Color? {
        if display.isCompleted { return nil }
        if display.isOutsideRepRange { return DesignSystem.Colors.warning }
        if display.isAtUpperRepLimit { return DesignSystem.Colors.tint }
        return nil
    }

    var body: some View {
        HStack(spacing: 0) {
            completionZone

            HStack(spacing: 8) {
                Text(String(format: "%02d", display.number))
                    .font(.system(size: 10.5, weight: .bold))
                    .monospacedDigit()
                    .kerning(0.6)
                    .foregroundStyle(numberColor)
                    .frame(width: 22, alignment: .leading)

                valueChip(
                    value: "\(display.reps)",
                    unit: "set.reps_unit".localized,
                    valueColor: repsColor,
                    field: .reps
                )

                Text("×")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.2))

                valueChip(
                    value: WorkoutValueFormatting.weight(display.weight),
                    unit: display.isAssistance ? "exercise.assistance".localized : "set.weight_unit".localized,
                    valueColor: nil,
                    field: .weight
                )

                if display.isOutsideRepRange && !display.isCompleted {
                    Circle()
                        .fill(DesignSystem.Colors.warning)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel("set.outside_rep_goal".localized)
                }

                Spacer(minLength: 0)

                if display.isCompleted, let completedAt = display.completedAt {
                    Text(completedAt, style: .time)
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.3))
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .padding(.vertical, 10)

            setMenu
        }
        .frame(minHeight: 62)
        .background(backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(DesignSystem.Animation.easeOut, value: display.isCompleted)
    }

    // MARK: - Completion zone

    /// Full-height 62pt hit area, separated from the values by its own background
    /// and a divider so it reads as a distinct target rather than "the row".
    private var completionZone: some View {
        Button(action: onToggleCompleted) {
            ZStack {
                Circle()
                    .fill(display.isCompleted ? DesignSystem.Colors.tint : Color.clear)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Circle()
                            .stroke(
                                isNext ? DesignSystem.Colors.tint : Color.white.opacity(0.28),
                                lineWidth: display.isCompleted ? 0 : 2
                            )
                    )
                    .overlay(
                        Circle()
                            .stroke(DesignSystem.Colors.tint.opacity(0.1), lineWidth: 5)
                            .opacity(isNext && !display.isCompleted ? 1 : 0)
                    )

                if display.isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(DesignSystem.Colors.textOnTint)
                }
            }
            .frame(width: 62)
            .frame(maxHeight: .infinity)
            .background(display.isCompleted ? DesignSystem.Colors.tint.opacity(0.14) : Color.white.opacity(0.03))
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(display.isCompleted ? DesignSystem.Colors.tint.opacity(0.2) : Color.white.opacity(0.06))
                    .frame(width: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            display.isCompleted
                ? "accessibility.set.uncomplete".localized(display.number)
                : "accessibility.set.complete".localized(display.number)
        )
    }

    // MARK: - Value chip

    /// The only editable target on the right side. Completed sets keep the chip
    /// tappable (values stay correctable) but drop its frame so the row reads as done.
    private func valueChip(value: String, unit: String, valueColor: Color?, field: WorkoutSetField) -> some View {
        Button {
            HapticManager.shared.light()
            onEdit(field)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 16.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(valueColor ?? (display.isCompleted ? Color.white.opacity(0.55) : .white))

                Text(unit)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(display.isCompleted ? 0.35 : 0.45))
            }
            .lineLimit(1)
            .padding(.horizontal, display.isCompleted ? 4 : 10)
            .padding(.vertical, 5)
            .frame(minHeight: 34)
            .background(display.isCompleted ? Color.clear : Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(display.isCompleted ? Color.clear : Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            field == .reps
                ? "accessibility.set.edit_reps".localized(display.number)
                : "accessibility.set.edit_weight".localized(display.number)
        )
        .accessibilityValue("\(value) \(unit)")
    }

    // MARK: - Set menu

    /// Replaces the actions that used to hide inside the expanded set editor.
    private var setMenu: some View {
        Menu {
            Section("set.number".localized(display.number)) {
                Button {
                    HapticManager.shared.light()
                    onDuplicate()
                } label: {
                    Label("set.duplicate".localized, systemImage: "plus.square.on.square")
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("set.delete".localized, systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.28))
                .frame(width: 40)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("set.actions".localized(display.number))
    }
}

#Preview {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        VStack(spacing: 8) {
            WorkoutSetRowView(
                display: WorkoutSetDisplay(
                    id: UUID(), number: 1, reps: 5, weight: 90, plannedReps: 5, plannedWeight: 90,
                    isCompleted: true, completedAt: Date(), isAssistance: false,
                    targetRepMin: 4, targetRepMax: 6
                ),
                isNext: false,
                onToggleCompleted: {}, onEdit: { _ in }, onDuplicate: {}, onDelete: {}
            )
            WorkoutSetRowView(
                display: WorkoutSetDisplay(
                    id: UUID(), number: 2, reps: 6, weight: 92.5, plannedReps: 5, plannedWeight: 90,
                    isCompleted: false, completedAt: nil, isAssistance: false,
                    targetRepMin: 4, targetRepMax: 6
                ),
                isNext: true,
                onToggleCompleted: {}, onEdit: { _ in }, onDuplicate: {}, onDelete: {}
            )
            WorkoutSetRowView(
                display: WorkoutSetDisplay(
                    id: UUID(), number: 3, reps: 9, weight: 90, plannedReps: 5, plannedWeight: 90,
                    isCompleted: false, completedAt: nil, isAssistance: false,
                    targetRepMin: 4, targetRepMax: 6
                ),
                isNext: false,
                onToggleCompleted: {}, onEdit: { _ in }, onDuplicate: {}, onDelete: {}
            )
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
