//
//  ProgressiveOverloadBanner.swift
//  GymStreak
//

import SwiftUI

struct ProgressiveOverloadBanner: View {
    let targetRepMax: Int
    var isAssistance: Bool = false
    let onIncrease: () -> Void
    let onDismiss: () -> Void

    /// At accessibility sizes the message and the two controls cannot share a
    /// line — the label would scale down to its floor and still truncate. The
    /// bar is persistent on the workout screen, so it stacks instead.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        icon
                        message
                    }
                    HStack(spacing: 8) {
                        increaseButton
                        Spacer(minLength: 4)
                        dismissButton
                    }
                }
            } else {
                HStack(spacing: 8) {
                    icon
                    message
                    Spacer(minLength: 4)
                    increaseButton
                    dismissButton
                }
            }
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

    private var icon: some View {
        Image(systemName: "arrow.up.circle.fill")
            .font(.caption)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.orange)
            .frame(width: 20, height: 20)
    }

    private var message: some View {
        Text("rep_range.all_sets_maxed".localized(targetRepMax))
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .minimumScaleFactor(0.75)
    }

    private var increaseButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onIncrease()
        } label: {
            Text((isAssistance ? "exercise.reduce_assistance" : "rep_range.increase").localized)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.textOnTint)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.orange, in: Capsule())
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(.borderless)
    }

    private var dismissButton: some View {
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
        .accessibilityLabel("action.dismiss".localized)
    }
}
