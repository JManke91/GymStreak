import SwiftUI
import UIKit

// MARK: - 1. ONYX DESIGN SYSTEM (Theme Definition)
// The DNA of the app: colors, fonts, spacing, and haptics.

struct DesignSystem {

    // MARK: - Colors
    struct Colors {
        // Primary Backgrounds
        static let background = Color.black // Pure OLED Black
        static let card = Color(red: 28/255, green: 28/255, blue: 30/255) // Dark Gray for Cards
        static let cardElevated = Color(red: 38/255, green: 38/255, blue: 40/255) // Elevated Card
        static let cardPressed = Color(red: 48/255, green: 48/255, blue: 52/255) // Pressed Card State
        static let input = Color(red: 44/255, green: 44/255, blue: 46/255) // Input Fields
        static let listRowBackground = Color(red: 28/255, green: 28/255, blue: 30/255) // List Row

        // Accents
        static let tint = Color(red: 0/255, green: 255/255, blue: 133/255) // Vibrant Green
        static let success = Color(red: 48/255, green: 209/255, blue: 88/255) // Vibrant Green
        static let destructive = Color(red: 255/255, green: 69/255, blue: 58/255) // Red
        static let warning = Color(red: 255/255, green: 159/255, blue: 10/255) // Orange
        static let info = Color(red: 94/255, green: 92/255, blue: 230/255) // Indigo

        // Text
        static let textPrimary = Color.white
        static let textSecondary = Color(white: 0.6) // 60% white
        static let textTertiary = Color(white: 0.4) // 40% white
        static let textDisabled = Color(white: 0.3) // 30% white
        static let textOnTint = Color.black // Dark text for use on tint color background

        // UI Elements
        static let border = Color(white: 0.2)
        static let divider = Color(white: 0.15)
        static let shimmer = Color(white: 0.12)
    }

    // MARK: - Spacing
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Dimensions
    struct Dimensions {
        // Corner Radii
        static let cornerRadius: CGFloat = 12 // Default
        static let cornerRadiusSM: CGFloat = 8
        static let cornerRadiusMD: CGFloat = 12
        static let cornerRadiusLG: CGFloat = 16
        static let cornerRadiusXL: CGFloat = 20

        // Input/Button Heights
        static let inputHeight: CGFloat = 36
        static let buttonHeight: CGFloat = 50
        static let buttonHeightCompact: CGFloat = 44

        // Icon Sizes
        static let iconSize: CGFloat = 24
        static let iconSizeSM: CGFloat = 16

        // Badge Sizes
        static let badgeSize: CGFloat = 40
        static let badgeSizeSM: CGFloat = 28

        // Card
        static let cardPadding: CGFloat = 16
        static let cardSpacing: CGFloat = 12
    }

    // MARK: - Animation Presets
    struct Animation {
        static let snappy = SwiftUI.Animation.snappy(duration: 0.35)
        static let spring = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.7)
        static let easeOut = SwiftUI.Animation.easeOut(duration: 0.25)
        static let linear = SwiftUI.Animation.linear(duration: 0.2)
    }
}

// MARK: - Typography
extension Font {
    // Display & Headers
    static let onyxDisplay = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let onyxTitle = Font.system(.title, design: .rounded).weight(.bold)
    static let onyxTitle2 = Font.system(.title2, design: .rounded).weight(.semibold)
    static let onyxHeader = Font.system(.title3, design: .rounded).weight(.semibold)
    static let onyxSubheadline = Font.system(.subheadline, design: .rounded).weight(.medium)

    // Body
    static let onyxBody = Font.system(.body, design: .default)

    // Captions
    static let onyxCaption = Font.system(.caption, design: .rounded).weight(.medium)
    static let onyxCaption2 = Font.system(.caption2, design: .rounded)

    // Numbers (Monospaced to prevent jumping)
    static let onyxNumber = Font.system(.body, design: .rounded).monospacedDigit().weight(.medium)
    static let onyxNumberLarge = Font.system(.title, design: .rounded).monospacedDigit().weight(.bold)
    static let onyxNumberSmall = Font.system(.caption, design: .rounded).monospacedDigit().weight(.medium)
}

// MARK: - Haptic Manager

class HapticManager {
    static let shared = HapticManager()

    func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

// MARK: - Preview

#Preview("Onyx Design System") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        VStack(spacing: 24) {
            Text("Onyx Design System")
                .font(.onyxTitle)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            HStack(spacing: 16) {
                Circle()
                    .fill(DesignSystem.Colors.tint)
                    .frame(width: 30, height: 30)

                Circle()
                    .fill(DesignSystem.Colors.success)
                    .frame(width: 30, height: 30)

                Circle()
                    .fill(DesignSystem.Colors.warning)
                    .frame(width: 30, height: 30)

                Circle()
                    .fill(DesignSystem.Colors.destructive)
                    .frame(width: 30, height: 30)
            }

            Text("100 kg × 10")
                .font(.onyxNumberLarge)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}