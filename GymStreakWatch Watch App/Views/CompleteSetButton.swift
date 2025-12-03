//
//  CompleteSetButton.swift
//  GymStreakWatch Watch App
//
//  Created by Claude Code
//

import SwiftUI
import WatchKit

/// A prominent button for completing/uncompleting a workout set
/// Uses visual state indicators (color + icon) for clear communication
struct CompleteSetButton: View {
    let isCompleted: Bool
    let onToggle: () -> Void

    var body: some View {
        Button {
            handleToggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)

                Text(isCompleted ? "Done" : "Complete")
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 36)
        }
        .buttonStyle(.borderedProminent)
        .tint(isCompleted ? .green : .blue)
        .buttonBorderShape(.roundedRectangle(radius: 10))
        .contentShape(Rectangle()) // Full tap area
        .accessibilityLabel(isCompleted ? "Set completed. Tap to mark incomplete" : "Complete set")
        .accessibilityHint(isCompleted ? "Double tap to undo completion" : "Double tap to complete set and start rest timer")
    }

    private func handleToggle() {
        // Play appropriate haptic based on action
        if isCompleted {
            WKInterfaceDevice.current().play(.directionDown) // Uncomplete (undo)
        } else {
            WKInterfaceDevice.current().play(.success) // Complete (positive action)
        }
        onToggle()
    }
}

// MARK: - Preview

#Preview("Incomplete State") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 20) {
            CompleteSetButton(isCompleted: false, onToggle: {})
                .padding()
        }
    }
}

#Preview("Completed State") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 20) {
            CompleteSetButton(isCompleted: true, onToggle: {})
                .padding()
        }
    }
}
