//
//  ConditioningProgramRoutinesCardView.swift
//  GymStreak
//
//  The conditioning program on the Routines tab: a dismissible invitation for
//  users who have not enrolled, the current week for those who have. Renders
//  nothing once a non-enrolled user closed it. See docs/fight-conditioning.md.
//

import SwiftUI

struct ConditioningProgramRoutinesCardView: View {
    let card: ConditioningProgramRoutinesCard
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: "figure.boxing")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.tint)
                    .frame(width: 40, height: 40)
                    .background(DesignSystem.Colors.tint.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if case .invitation = card {
                    // Room for the dismiss button overlaid below — a button nested
                    // inside this one would not reliably get its own taps.
                    Color.clear.frame(width: 28, height: 28)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusLG, style: .continuous)
                    .fill(DesignSystem.Colors.card)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if case .invitation = card {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .accessibilityLabel("conditioning.program.card.dismiss".localized)
            }
        }
    }

    private var title: String {
        switch card {
        case .invitation: "conditioning.program.card.invite.title".localized
        case .enrolled: "conditioning.program.card.enrolled.title".localized
        }
    }

    private var subtitle: String {
        switch card {
        case .invitation: "conditioning.program.invite.subtitle".localized
        case .enrolled(let status): ConditioningProgramCopy.status(status)
        }
    }
}
