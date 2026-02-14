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
        case .primary:
            return DesignSystem.Colors.textOnTint
        case .destructive:
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

// MARK: - Onyx Prominent Button Style

/// A ButtonStyle for prominent actions that uses the app tint color with dark text
/// Use this instead of .borderedProminent when you want dark text on the green background
struct OnyxProminentButtonStyle: ButtonStyle {
    let backgroundColor: Color
    let foregroundColor: Color

    @Environment(\.isEnabled) private var isEnabled

    init(backgroundColor: Color = DesignSystem.Colors.tint, foregroundColor: Color = DesignSystem.Colors.textOnTint) {
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(backgroundColor)
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .opacity(isEnabled ? 1.0 : 0.5)
    }
}

extension ButtonStyle where Self == OnyxProminentButtonStyle {
    /// Default prominent style with tint color and dark text
    static var onyxProminent: OnyxProminentButtonStyle { OnyxProminentButtonStyle() }

    /// Prominent style with custom colors
    static func onyxProminent(backgroundColor: Color, foregroundColor: Color = .white) -> OnyxProminentButtonStyle {
        OnyxProminentButtonStyle(backgroundColor: backgroundColor, foregroundColor: foregroundColor)
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
