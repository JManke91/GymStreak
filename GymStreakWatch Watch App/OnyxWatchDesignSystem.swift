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
        static let tint = Color(red: 0/255, green: 255/255, blue: 133/255) // Vibrant Green
        static let success = Color(red: 48/255, green: 209/255, blue: 88/255) // Vibrant Green
        static let destructive = Color(red: 255/255, green: 69/255, blue: 58/255) // Red
        static let warning = Color(red: 255/255, green: 159/255, blue: 10/255) // Orange

        // Text
        static let textPrimary = Color.white
        static let textSecondary = Color(white: 0.6)
        static let textTertiary = Color(white: 0.4)
        static let textOnTint = Color.black // Dark text for use on tint color background

        // UI Elements
        static let divider = Color(white: 0.15)

        // Active Workout Screen (glass design, see docs/watch-set-completion-button.md)
        static let accentGreen = Color(red: 52/255, green: 224/255, blue: 122/255) // #34E07A
        static let surfaceCardActive = Color(red: 12/255, green: 36/255, blue: 23/255) // #0C2417
        static let stepperGreen = Color(red: 29/255, green: 81/255, blue: 56/255) // #1D5138
        static let stepperIcon = Color(red: 99/255, green: 239/255, blue: 155/255) // #63EF9B
        static let strokeSubtle = Color(red: 58/255, green: 58/255, blue: 60/255) // #3A3A3C
        static let segmentTrack = Color(red: 42/255, green: 42/255, blue: 44/255) // #2A2A2C (top workout-progress bar track)
        static let segmentFill = Color(red: 92/255, green: 92/255, blue: 96/255) // #5C5C60 (neutral routine-progress fill — green is reserved for the current set)
        static let textMuted = Color(red: 152/255, green: 152/255, blue: 157/255) // #98989D
        static let chipBackground = Color(red: 26/255, green: 26/255, blue: 28/255) // #1A1A1C
        static let chipText = Color(red: 199/255, green: 199/255, blue: 204/255) // #C7C7CC
        static let glassLabel = Color(red: 234/255, green: 255/255, blue: 242/255) // #EAFFF2
        static let completeCheckmark = Color(red: 141/255, green: 255/255, blue: 187/255) // #8DFFBB (icon-only Complete-button checkmark, brighter than accent)
        static let textOnDone = Color(red: 3/255, green: 20/255, blue: 10/255) // #03140A
        static let doneGradient = [
            Color(red: 109/255, green: 255/255, blue: 168/255), // #6DFFA8
            Color(red: 47/255, green: 216/255, blue: 115/255),  // #2FD873
            Color(red: 23/255, green: 180/255, blue: 90/255)    // #17B45A
        ]
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
