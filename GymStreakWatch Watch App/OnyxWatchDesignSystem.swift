//
//  OnyxWatchDesignSystem.swift
//  GymStreakWatch Watch App
//
//  Onyx Design System adapted for watchOS with appropriate sizing and touch targets
//

import SwiftUI

// MARK: - Watch Design System

struct OnyxWatch {

    // MARK: - Colors (Same as iOS)
    struct Colors {
        // Primary Backgrounds
        static let background = Color.black // Pure OLED Black
        static let card = Color(red: 28/255, green: 28/255, blue: 30/255) // Dark Gray for Cards
        static let cardElevated = Color(red: 38/255, green: 38/255, blue: 40/255) // Elevated Card
        static let cardPressed = Color(red: 48/255, green: 48/255, blue: 52/255) // Pressed Card State
        static let input = Color(red: 44/255, green: 44/255, blue: 46/255) // Input Fields

        // Accents
        static let tint = Color(red: 10/255, green: 132/255, blue: 255/255) // Electric Blue
        static let success = Color(red: 48/255, green: 209/255, blue: 88/255) // Vibrant Green
        static let destructive = Color(red: 255/255, green: 69/255, blue: 58/255) // Red
        static let warning = Color(red: 255/255, green: 159/255, blue: 10/255) // Orange

        // Text
        static let textPrimary = Color.white
        static let textSecondary = Color(white: 0.6)
        static let textTertiary = Color(white: 0.4)

        // UI Elements
        static let divider = Color(white: 0.15)
    }

    // MARK: - Spacing (Smaller for Watch)
    struct Spacing {
        static let xs: CGFloat = 2
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
    }

    // MARK: - Dimensions (Watch-specific)
    struct Dimensions {
        // Corner Radii (Smaller for Watch)
        static let cornerRadiusSM: CGFloat = 6
        static let cornerRadiusMD: CGFloat = 8
        static let cornerRadiusLG: CGFloat = 12

        // Touch Targets (44pt minimum per Apple guidelines)
        static let minTouchTarget: CGFloat = 44

        // Button Heights
        static let buttonHeight: CGFloat = 44

        // Icon Sizes
        static let iconSize: CGFloat = 20
        static let iconSizeSM: CGFloat = 14
    }
}

// MARK: - Watch Typography

extension Font {
    // Display & Headers
    static let watchDisplay = Font.system(.title, design: .rounded).weight(.bold)
    static let watchHeader = Font.system(.headline, design: .rounded).weight(.semibold)
    static let watchSubheadline = Font.system(.subheadline, design: .rounded).weight(.medium)

    // Body
    static let watchBody = Font.system(.body, design: .default)

    // Captions
    static let watchCaption = Font.system(.caption, design: .rounded).weight(.medium)
    static let watchCaption2 = Font.system(.caption2, design: .rounded)

    // Numbers (Monospaced)
    static let watchNumber = Font.system(.body, design: .rounded).monospacedDigit().weight(.semibold)
    static let watchNumberLarge = Font.system(.title2, design: .rounded).monospacedDigit().weight(.bold)
    static let watchNumberSmall = Font.system(.caption, design: .rounded).monospacedDigit().weight(.medium)
}

// MARK: - Preview

#Preview {
    ZStack {
        OnyxWatch.Colors.background.ignoresSafeArea()

        VStack(spacing: 12) {
            Text("Onyx Watch")
                .font(.watchDisplay)
                .foregroundStyle(OnyxWatch.Colors.textPrimary)

            Text("Design System")
                .font(.watchHeader)
                .foregroundStyle(OnyxWatch.Colors.tint)

            HStack(spacing: 16) {
                Circle()
                    .fill(OnyxWatch.Colors.success)
                    .frame(width: 20, height: 20)

                Circle()
                    .fill(OnyxWatch.Colors.warning)
                    .frame(width: 20, height: 20)

                Circle()
                    .fill(OnyxWatch.Colors.destructive)
                    .frame(width: 20, height: 20)
            }

            Text("135 kg × 10")
                .font(.watchNumberLarge)
                .foregroundStyle(OnyxWatch.Colors.textPrimary)
        }
        .padding()
    }
}
