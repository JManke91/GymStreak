//
//  RoutineParameterChips.swift
//  GymStreak
//
//  The parameter strip of an exercise card in the routine detail (redesign v2):
//  chips that read like labels but act like controls. The inline editors they
//  open live in RoutineParameterEditors.swift.
//

import SwiftUI

/// The two per-exercise parameters editable straight from the card's chip strip.
enum ExerciseCardParameter {
    case rest
    case repRange
}

// MARK: - Chip strip

/// Pause + rep-goal chips shown under an exercise header. Tapping a chip toggles
/// its inline editor, which the caller renders directly below this strip.
struct ExerciseParameterChips: View {
    let restTime: TimeInterval
    let targetRepMin: Int?
    let targetRepMax: Int?
    @Binding var openParameter: ExerciseCardParameter?

    var body: some View {
        HStack(spacing: 6) {
            ParameterChipButton(
                icon: restTime > 0 ? "timer" : "timer.slash",
                label: "rest_timer.rest_short".localized,
                value: restTime > 0 ? TimeFormatting.formatRestTime(restTime) : "rest_timer.off".localized,
                isActive: openParameter == .rest
            ) {
                toggle(.rest)
            }

            if let min = targetRepMin, let max = targetRepMax {
                ParameterChipButton(
                    icon: "target",
                    label: "rep_range.goal_short".localized,
                    value: "rep_range.value".localized(min, max),
                    isActive: openParameter == .repRange
                ) {
                    toggle(.repRange)
                }
            } else {
                ParameterChipButton(
                    icon: "target",
                    value: "rep_range.set_goal".localized,
                    isActive: openParameter == .repRange,
                    isGhost: true
                ) {
                    toggle(.repRange)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func toggle(_ parameter: ExerciseCardParameter) {
        HapticManager.shared.light()
        withAnimation(DesignSystem.Animation.spring) {
            openParameter = openParameter == parameter ? nil : parameter
        }
    }
}

// MARK: - Chip

/// Parameter chip: a label + value pill. `isActive` marks the chip whose inline
/// editor is currently open; `isGhost` is the "not configured yet" affordance.
struct ParameterChipButton: View {
    let icon: String
    var label: String? = nil
    let value: String
    var isActive: Bool = false
    var isGhost: Bool = false
    let action: () -> Void

    private var valueColor: Color {
        if isActive { return DesignSystem.Colors.tint }
        return isGhost ? Color.white.opacity(0.5) : Color.white.opacity(0.85)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isActive ? DesignSystem.Colors.tint : Color.white.opacity(0.55))

                if let label {
                    Text(label)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(isActive ? DesignSystem.Colors.tint : Color.white.opacity(0.5))
                }

                Text(value)
                    .font(.system(size: 11.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
            }
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(isActive ? DesignSystem.Colors.tint.opacity(0.14) : (isGhost ? Color.clear : Color.white.opacity(0.05)))
            .overlay(chipBorder)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var chipBorder: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        if isActive {
            shape.stroke(DesignSystem.Colors.tint.opacity(0.45), lineWidth: 1)
        } else if isGhost {
            shape.stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(Color.white.opacity(0.16))
        } else {
            shape.stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }
}
