//
//  ProgressiveOverloadBanner.swift
//  GymStreak
//

import SwiftUI

struct ProgressiveOverloadBanner: View {
    let targetRepMax: Int
    let onIncrease: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.caption)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
                .frame(width: 20, height: 20)

            Text("rep_range.all_sets_maxed".localized(targetRepMax))
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 4)

            // Increase button
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onIncrease()
            } label: {
                Text("rep_range.increase".localized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textOnTint)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.orange, in: Capsule())
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(.borderless)

            // Dismiss button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
