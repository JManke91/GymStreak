//
//  ConditioningProgramWeekRail.swift
//  GymStreak
//
//  The twelve weeks as three labelled, tappable blocks. It carries the week
//  range and the phase name, so the bar and the phase cards below it are
//  obviously the same three things. See docs/fight-conditioning.md.
//

import SwiftUI

struct ConditioningProgramWeekRail: View {
    /// The phase whose card is open, highlighted here.
    var selected: ConditioningEnergySystem?
    /// The phase the program is in, highlighted but not announced as selected.
    var current: ConditioningEnergySystem?
    /// The week the user is in; its block is filled up to that week.
    var currentWeek: Int?
    var onSelect: ((ConditioningEnergySystem) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            // Three constant phases — a plain stack is fine.
            ForEach(ConditioningProgramContent.phases) { phase in
                block(phase)
            }
        }
    }

    private func block(_ phase: ConditioningProgramPhase) -> some View {
        let accent = ConditioningProgramPhaseCard.accent(phase.system)
        let isSelected = selected == phase.system || current == phase.system
        let isOpen = selected == phase.system
        return Button {
            HapticManager.shared.selection()
            onSelect?(phase.system)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 3) {
                    ForEach(Array(phase.weeks), id: \.self) { week in
                        Capsule()
                            .fill(accent.opacity(fillOpacity(week: week, isSelected: isSelected)))
                            .frame(height: 8)
                    }
                }
                Text(ConditioningProgramCopy.phaseWeeks(phase).uppercased())
                    .font(.onyxMonoLabel)
                    .kerning(0.6)
                    .foregroundStyle(isSelected ? accent : DesignSystem.Colors.textTertiary)
                Text(ConditioningProgramCopy.phaseShortTitle(phase.system))
                    .font(.onyxCaption)
                    .foregroundStyle(isSelected ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onSelect == nil)
        .accessibilityLabel(ConditioningProgramCopy.phaseAccessibilityLabel(phase))
        .accessibilityAddTraits(isOpen ? .isSelected : [])
    }

    /// With a running program the bar is progress; without one it is a diagram,
    /// and the selected block simply reads as the brighter one.
    private func fillOpacity(week: Int, isSelected: Bool) -> Double {
        guard let currentWeek else { return isSelected ? 1 : 0.35 }
        return week <= currentWeek ? 1 : 0.2
    }
}
