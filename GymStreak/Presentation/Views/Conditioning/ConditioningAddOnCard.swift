//
//  ConditioningAddOnCard.swift
//  GymStreak
//
//  The post-workout conditioning add-on, as it appears on the iPhone workout
//  summary. Value input only — the decision was made by
//  `ConditioningProgramCoach.addOn`. See docs/fight-conditioning.md (ticket 05).
//

import SwiftUI

struct ConditioningAddOnCard: View {

    let offer: ConditioningAddOnOffer
    /// Set once a reminder is scheduled: replaces the buttons with a confirmation.
    let remindedAt: Date?
    /// The user asked to be reminded, but notifications are not granted.
    let isReminderUnavailable: Bool
    let onStart: () -> Void
    let onRemindLater: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        switch offer {
        case .none:
            EmptyView()
        case .startNow(let target):
            card(target: target, isHard: false, notBefore: nil)
        case .later(let target, let notBefore):
            card(target: target, isHard: true, notBefore: notBefore)
        }
    }

    // MARK: - Card

    private func card(target: ConditioningProgramTarget, isHard: Bool, notBefore: Date?) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            header(isHard: isHard)

            Text(ConditioningProgramCopy.addOnSession(target))
                .font(.onyxSubheadline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(detail(isHard: isHard, notBefore: notBefore))
                .font(.onyxFootnote)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            actions(isHard: isHard)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(isHard: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "figure.boxing")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.tint)
            Text(isHard ? "conditioning.addon.later.title".localized : "conditioning.addon.now.title".localized)
                .font(.onyxHeader)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Spacer(minLength: 0)
            // The one-tap dismissal the ticket requires. It never touches the
            // save — this card is a passenger on the summary form.
            Button {
                HapticManager.shared.light()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .padding(DesignSystem.Spacing.xs)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("action.dismiss".localized)
        }
    }

    private func detail(isHard: Bool, notBefore: Date?) -> String {
        guard isHard, let notBefore else { return "conditioning.addon.now.detail".localized }
        return ConditioningProgramCopy.addOnLaterDetail(notBefore: notBefore)
    }

    // MARK: - Actions

    @ViewBuilder
    private func actions(isHard: Bool) -> some View {
        if let remindedAt {
            Label(ConditioningProgramCopy.addOnReminded(at: remindedAt), systemImage: "bell.fill")
                .font(.onyxFootnote)
                .foregroundStyle(DesignSystem.Colors.tint)
                .fixedSize(horizontal: false, vertical: true)
        } else if isReminderUnavailable {
            Label("conditioning.addon.reminder_unavailable".localized, systemImage: "bell.slash")
                .font(.onyxFootnote)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if isHard {
            VStack(spacing: DesignSystem.Spacing.sm) {
                Button {
                    HapticManager.shared.light()
                    onRemindLater()
                } label: {
                    Text("conditioning.addon.remind_later".localized)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.onyxProminent)

                // The explicit override. The card has already said why this is
                // the worse option; the app does not know the rest of the
                // user's day, so it does not get to refuse.
                Button {
                    HapticManager.shared.light()
                    onStart()
                } label: {
                    Text("conditioning.addon.start_anyway".localized)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .font(.onyxFootnote)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        } else {
            Button {
                HapticManager.shared.medium()
                onStart()
            } label: {
                Text("conditioning.addon.start_now".localized)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.onyxProminent)
        }
    }
}
