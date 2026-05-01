//
//  WorkoutTypeChip.swift
//  GymStreak
//

import SwiftUI

/// Uppercased pill chip used in workout cards and the workout-detail header.
struct WorkoutTypeChip: View {
    let type: WorkoutType
    var size: Size = .medium

    enum Size { case small, medium }

    var body: some View {
        Text(type.label.uppercased())
            .font(.system(size: fontSize, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(type.color)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                Capsule().fill(type.color.opacity(0.14))
            )
    }

    private var fontSize: CGFloat { size == .small ? 10 : 11 }
    private var horizontalPadding: CGFloat { size == .small ? 8 : 10 }
    private var verticalPadding: CGFloat { size == .small ? 2 : 3 }
}

#Preview {
    VStack(spacing: 12) {
        WorkoutTypeChip(type: .push)
        WorkoutTypeChip(type: .pull)
        WorkoutTypeChip(type: .legs, size: .small)
        WorkoutTypeChip(type: .core)
        WorkoutTypeChip(type: .fullBody)
    }
    .padding()
    .background(DesignSystem.Colors.background)
    .preferredColorScheme(.dark)
}
