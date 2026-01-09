//
//  ApplyToAllBanner.swift
//  GymStreak
//
//  A reusable banner component for "Apply to All Sets" functionality
//

import SwiftUI

enum ApplyToAllType {
    case reps
    case weight

    var icon: String {
        switch self {
        case .reps: return "number.circle"
        case .weight: return "scalemass"
        }
    }

    var label: String {
        switch self {
        case .reps: return "reps"
        case .weight: return "weight"
        }
    }
}

struct ApplyToAllBanner: View {
    let type: ApplyToAllType?
    let setCount: Int
    let onApply: () -> Void
    let onDismiss: () -> Void

    // Convenience initializer for backward compatibility (applies to both reps and weight)
    init(setCount: Int, onApply: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.type = nil
        self.setCount = setCount
        self.onApply = onApply
        self.onDismiss = onDismiss
    }

    // New initializer with specific type
    init(type: ApplyToAllType, setCount: Int, onApply: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.type = type
        self.setCount = setCount
        self.onApply = onApply
        self.onDismiss = onDismiss
    }

    private var icon: String {
        type?.icon ?? "square.on.square"
    }

    private var labelText: String {
        if let type = type {
            return "Apply \(type.label) to all \(setCount)?"
        } else {
            return "Apply to all \(setCount)?"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.appAccent)
                .frame(width: 20, height: 20)

            Text(labelText)
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
                    .background(Color.neonGreen, in: Capsule())
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
                .strokeBorder(Color.appAccent.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview("Apply to All Banner") {
    VStack(spacing: 16) {
        ApplyToAllBanner(
            type: .reps,
            setCount: 4,
            onApply: { print("Applied reps to all sets") },
            onDismiss: { print("Dismissed") }
        )

        ApplyToAllBanner(
            type: .weight,
            setCount: 4,
            onApply: { print("Applied weight to all sets") },
            onDismiss: { print("Dismissed") }
        )
    }
    .padding()
}
