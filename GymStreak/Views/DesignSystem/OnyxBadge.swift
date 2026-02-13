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

/// A muscle group badge using the app's tint color for visual consistency
struct OnyxMuscleGroupBadge: View {
    let muscleGroups: [String]
    var isActive: Bool = true
    var size: OnyxBadgeSize = .regular

    private var abbreviation: String {
        MuscleGroups.abbreviation(for: muscleGroups)
    }

    var body: some View {
        OnyxBadge(
            text: abbreviation,
            color: DesignSystem.Colors.tint,
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
                OnyxBadge(text: "CH", color: DesignSystem.Colors.tint, isActive: true)
                OnyxBadge(text: "BI", color: DesignSystem.Colors.tint, isActive: true)
                OnyxBadge(text: "AB", color: DesignSystem.Colors.tint, isActive: true)
            }

            HStack(spacing: 12) {
                OnyxBadge(text: "QD", color: DesignSystem.Colors.tint, isActive: true)
                OnyxBadge(text: "GL", color: DesignSystem.Colors.tint, isActive: true)
                OnyxBadge(text: "CF", color: DesignSystem.Colors.tint, isActive: true)
            }

            HStack(spacing: 12) {
                OnyxBadge(text: "CH", color: DesignSystem.Colors.tint, isActive: false)
                OnyxBadge(text: "AB", color: DesignSystem.Colors.tint, isActive: false)
                OnyxBadge(text: "QD", color: DesignSystem.Colors.tint, isActive: false)
            }

            HStack(spacing: 12) {
                OnyxBadge(text: "SM", color: DesignSystem.Colors.tint, size: .small)
                OnyxBadge(text: "SM", color: DesignSystem.Colors.success, size: .small)
                OnyxBadge(text: "SM", color: DesignSystem.Colors.warning, size: .small)
            }
        }
        .padding()
    }
}
