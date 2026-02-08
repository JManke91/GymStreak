//
//  OnyxButton.swift
//  GymStreak
//
//  Button styles for the Onyx Design System
//

import SwiftUI

/// Button style variants for Onyx Design System
enum OnyxButtonStyle {
    case primary
    case secondary
    case destructive
    case ghost
}

/// A styled button conforming to the Onyx Design System
struct OnyxButton: View {
    let title: String
    let icon: String?
    let style: OnyxButtonStyle
    let isCompact: Bool
    let action: () -> Void

    init(
        _ title: String,
        icon: String? = nil,
        style: OnyxButtonStyle = .primary,
        isCompact: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.isCompact = isCompact
        self.action = action
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:
            return DesignSystem.Colors.tint
        case .secondary:
            return DesignSystem.Colors.input
        case .destructive:
            return DesignSystem.Colors.destructive
        case .ghost:
            return Color.clear
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary, .destructive:
            return .white
        case .secondary:
            return DesignSystem.Colors.textPrimary
        case .ghost:
            return DesignSystem.Colors.tint
        }
    }

    private var height: CGFloat {
        isCompact ? DesignSystem.Dimensions.buttonHeightCompact : DesignSystem.Dimensions.buttonHeight
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                }
                Text(title)
                    .font(.onyxSubheadline)
            }
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusMD)
                    .fill(backgroundColor)
            )
            .overlay {
                if style == .ghost {
                    RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusMD)
                        .strokeBorder(DesignSystem.Colors.tint, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Button Styles") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        VStack(spacing: 16) {
            OnyxButton("Start Workout", icon: "play.circle.fill", style: .primary) { }

            OnyxButton("Add Set", style: .secondary) { }

            OnyxButton("Delete", icon: "trash", style: .destructive) { }

            OnyxButton("Cancel", style: .ghost) { }

            OnyxButton("Compact", style: .primary, isCompact: true) { }
        }
        .padding()
    }
}
