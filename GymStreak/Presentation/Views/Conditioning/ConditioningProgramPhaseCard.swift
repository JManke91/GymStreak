//
//  ConditioningProgramPhaseCard.swift
//  GymStreak
//
//  One phase of the 12-week program, as a card that expands in place: its weeks,
//  what it emphasizes, and — when given — the weekly targets of the user's own
//  plan. Pure value input, so the showcase, the program timeline and the
//  ticket-08 blurred preview of Phases 2–3 all render the same card.
//  See docs/fight-conditioning.md.
//

import SwiftUI

struct ConditioningProgramPhaseCard: View {
    let phase: ConditioningProgramPhase
    /// Weekly targets to list while expanded; empty hides the list.
    let targets: [ConditioningProgramTarget]
    var isExpanded = false
    /// The week the user is in, when it falls in this phase.
    var currentWeek: Int?
    /// The phase lies behind the user.
    var isPast = false
    /// Draws the line down to the next phase. Off where the card stands alone —
    /// on the dashboard only the tapped phase renders, and the line would run
    /// down to nothing.
    var showsConnector = true
    var onTap: (() -> Void)?

    private var accentColor: Color { ConditioningProgramPhaseCard.accent(phase.system) }
    private var isCurrent: Bool { currentWeek.map(phase.weeks.contains) ?? false }

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            rail
            Button {
                HapticManager.shared.selection()
                onTap?()
            } label: {
                card
            }
            .buttonStyle(.plain)
            .disabled(onTap == nil)
        }
    }

    /// The numbered node and the line that ties the three phases into one timeline.
    private var rail: some View {
        VStack(spacing: 4) {
            Text("\(ConditioningProgramContent.number(of: phase))")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(isPast || isExpanded ? DesignSystem.Colors.textOnTint : accentColor)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(isPast || isExpanded ? accentColor : accentColor.opacity(0.12))
                        .overlay(Circle().strokeBorder(accentColor, lineWidth: 2))
                )
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [accentColor, DesignSystem.Colors.divider],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .opacity(showsConnector && ConditioningProgramContent.number(of: phase) < ConditioningProgramContent.phases.count ? 1 : 0)
        }
        .padding(.top, DesignSystem.Spacing.lg)
        .accessibilityHidden(true)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            header
            Text(isExpanded
                 ? ConditioningProgramCopy.phaseDetail(phase.system)
                 : ConditioningProgramCopy.phaseTeaser(phase.system))
                .font(.onyxFootnote)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if isExpanded {
                if !targets.isEmpty {
                    Divider().overlay(DesignSystem.Colors.divider)
                    weekExample
                }
                Text(ConditioningProgramCopy.phaseRule(phase.system))
                    .font(.onyxCaption)
                    .foregroundStyle(accentColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Dimensions.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusLG)
                .fill(isExpanded ? accentColor.opacity(0.08) : DesignSystem.Colors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusLG)
                .strokeBorder(isExpanded ? accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    private var header: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ConditioningProgramCopy.phaseWeeksAndSystem(phase).uppercased())
                    .font(.onyxMonoLabel)
                    .kerning(0.7)
                    .foregroundStyle(accentColor)
                Text(ConditioningProgramCopy.phaseTitle(phase.system))
                    .font(.onyxHeader)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }
            Spacer(minLength: 0)
            if isCurrent {
                Text("conditioning.program.phase.current".localized.uppercased())
                    .font(.onyxMonoLabel)
                    .kerning(0.5)
                    .foregroundStyle(DesignSystem.Colors.textOnTint)
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(accentColor))
            } else if isPast {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(accentColor)
                    .accessibilityLabel("conditioning.program.phase.done".localized)
            }
            if onTap != nil {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
        }
    }

    private var weekExample: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("conditioning.program.week_example".localized.uppercased())
                .font(.onyxMonoLabel)
                .kerning(0.7)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            // At most three targets — a plain stack is fine.
            ForEach(targets) { target in
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 5, height: 5)
                    Text(ConditioningCopy.title(target.session))
                        .font(.onyxFootnote)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Spacer(minLength: 0)
                    Text("\(target.count) × \(ConditioningProgramCopy.volume(target))")
                        .font(.onyxNumberSmall)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
        }
    }

    // MARK: - Phase identity

    /// The intensity ramp of the three blocks: easy green → hard amber → maximal
    /// coral. `tint` and `warning` are the design system's; the coral exists only
    /// here, because `destructive` red reads as an error.
    static func accent(_ system: ConditioningEnergySystem) -> Color {
        switch system {
        case .aerobic: DesignSystem.Colors.tint
        case .lactic: DesignSystem.Colors.warning
        case .alactic: Color(red: 1.0, green: 0.42, blue: 0.35)
        }
    }

    static func symbol(_ system: ConditioningEnergySystem) -> String {
        switch system {
        case .aerobic: "wind"
        case .lactic: "flame.fill"
        case .alactic: "bolt.fill"
        }
    }
}
