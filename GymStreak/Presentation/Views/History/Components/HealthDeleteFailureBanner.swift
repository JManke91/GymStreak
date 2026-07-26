//
//  HealthDeleteFailureBanner.swift
//  GymStreak
//

import SwiftUI

/// Non-blocking notice shown on the History tab when a workout was deleted in
/// GymStreak but its Apple Health counterpart could not be removed.
///
/// Deliberately not a modal: the local deletion succeeded and there is nothing
/// the user must decide. The only consequence is that the workout is still in
/// the Health app, which they can remove there — so this informs and gets out
/// of the way rather than demanding a dismissal.
struct HealthDeleteFailureBanner: View {
    var onDismiss: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "heart.slash")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.warning)
                .padding(.top, 1)

            Text("history.delete.health_failed".localized)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("action.dismiss".localized)
        }
        .padding(14)
        .background(DesignSystem.Colors.warning.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignSystem.Colors.warning.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
