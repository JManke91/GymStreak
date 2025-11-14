//
//  ApplyToAllBanner.swift
//  GymStreak
//
//  A reusable banner component for "Apply to All Sets" functionality
//

import SwiftUI

struct ApplyToAllBanner: View {
    let setCount: Int
    let onApply: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.on.square")
                .font(.caption)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
                .frame(width: 20, height: 20)

            Text("Apply to all \(setCount)?")
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 4)

            // Apply to All button
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onApply()
            } label: {
                Text("Apply")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.blue, in: Capsule())
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
                .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview("Apply to All Banner") {
    VStack(spacing: 16) {
        ApplyToAllBanner(
            setCount: 4,
            onApply: { print("Applied to all sets") },
            onDismiss: { print("Dismissed") }
        )
    }
    .padding()
}
