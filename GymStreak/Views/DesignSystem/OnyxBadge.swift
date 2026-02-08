//
//  OnyxBadge.swift
//  GymStreak
//
//  Muscle group badges with body-region colors for the Onyx Design System
//

import SwiftUI

/// Badge size variants
enum OnyxBadgeSize {
    case small   // 28x28
    case regular // 40x40

    var dimension: CGFloat {
        switch self {
        case .small: return DesignSystem.Dimensions.badgeSizeSM
        case .regular: return DesignSystem.Dimensions.badgeSize
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .small: return 10
        case .regular: return 13
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .small: return 6
        case .regular: return 10
        }
    }
}

/// A badge displaying a muscle group abbreviation with Onyx styling
struct OnyxBadge: View {
    let text: String
    let color: Color
    var isActive: Bool = true
    var size: OnyxBadgeSize = .regular

    var body: some View {
        Text(text)
            .font(.system(size: size.fontSize, weight: .bold, design: .rounded))
            .foregroundStyle(isActive ? .white : DesignSystem.Colors.textSecondary)
            .frame(width: size.dimension, height: size.dimension)
            .background(
                RoundedRectangle(cornerRadius: size.cornerRadius)
                    .fill(isActive ? color : DesignSystem.Colors.textDisabled.opacity(0.3))
            )
    }
}

/// A muscle group badge using the body region color system
struct OnyxMuscleGroupBadge: View {
    let muscleGroups: [String]
    var isActive: Bool = true
    var size: OnyxBadgeSize = .regular

    private var abbreviation: String {
        MuscleGroups.abbreviation(for: muscleGroups)
    }

    private var regionColor: Color {
        MuscleGroups.bodyRegion(for: muscleGroups).color
    }

    var body: some View {
        OnyxBadge(
            text: abbreviation,
            color: regionColor,
            isActive: isActive,
            size: size
        )
    }
}

// MARK: - Previews

#Preview("Badges") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        VStack(spacing: 16) {
            HStack(spacing: 12) {
                OnyxBadge(text: "CH", color: .blue, isActive: true)
                OnyxBadge(text: "BI", color: .blue, isActive: true)
                OnyxBadge(text: "AB", color: .orange, isActive: true)
            }

            HStack(spacing: 12) {
                OnyxBadge(text: "QD", color: .green, isActive: true)
                OnyxBadge(text: "GL", color: .green, isActive: true)
                OnyxBadge(text: "CF", color: .green, isActive: true)
            }

            HStack(spacing: 12) {
                OnyxBadge(text: "CH", color: .blue, isActive: false)
                OnyxBadge(text: "AB", color: .orange, isActive: false)
                OnyxBadge(text: "QD", color: .green, isActive: false)
            }

            HStack(spacing: 12) {
                OnyxBadge(text: "SM", color: .blue, size: .small)
                OnyxBadge(text: "SM", color: .orange, size: .small)
                OnyxBadge(text: "SM", color: .green, size: .small)
            }
        }
        .padding()
    }
}
