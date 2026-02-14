import SwiftUI

/// Available sizes for the muscle group badge
enum MuscleGroupBadgeSize {
    case small   // 28x28 - for compact contexts like picker rows
    case regular // 40x40 - default size for exercise lists

    var dimension: CGFloat {
        switch self {
        case .small: return 28
        case .regular: return 40
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

/// A badge displaying a muscle group abbreviation in a colored square
/// Uses the app's tint color for visual consistency
struct MuscleGroupAbbreviationBadge: View {
    let muscleGroups: [String]
    var isActive: Bool = true
    var size: MuscleGroupBadgeSize = .regular

    private var abbreviation: String {
        MuscleGroups.abbreviation(for: muscleGroups)
    }

    var body: some View {
        Text(abbreviation)
            .font(.system(size: size.fontSize, weight: .bold, design: .rounded))
            .foregroundStyle(isActive ? DesignSystem.Colors.textOnTint : .secondary)
            .frame(width: size.dimension, height: size.dimension)
            .background(
                RoundedRectangle(cornerRadius: size.cornerRadius)
                    .fill(isActive ? DesignSystem.Colors.tint : Color.secondary.opacity(0.2))
            )
    }
}

#Preview {
    VStack(spacing: 16) {
        HStack(spacing: 12) {
            MuscleGroupAbbreviationBadge(muscleGroups: ["Biceps"])
            MuscleGroupAbbreviationBadge(muscleGroups: ["Chest"])
            MuscleGroupAbbreviationBadge(muscleGroups: ["Lats"])
        }
        HStack(spacing: 12) {
            MuscleGroupAbbreviationBadge(muscleGroups: ["Abs"])
            MuscleGroupAbbreviationBadge(muscleGroups: ["Obliques"])
        }
        HStack(spacing: 12) {
            MuscleGroupAbbreviationBadge(muscleGroups: ["Quadriceps"])
            MuscleGroupAbbreviationBadge(muscleGroups: ["Glutes"])
            MuscleGroupAbbreviationBadge(muscleGroups: ["Calves"])
        }
        HStack(spacing: 12) {
            MuscleGroupAbbreviationBadge(muscleGroups: ["Biceps"], isActive: false)
            MuscleGroupAbbreviationBadge(muscleGroups: ["Abs"], isActive: false)
            MuscleGroupAbbreviationBadge(muscleGroups: ["Quadriceps"], isActive: false)
        }
    }
    .padding()
}
