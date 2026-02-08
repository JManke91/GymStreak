//
//  OnyxCard.swift
//  GymStreak
//
//  Card container with optional highlight state for the Onyx Design System
//

import SwiftUI

/// A card container styled with Onyx Design System colors
struct OnyxCard<Content: View>: View {
    let isHighlighted: Bool
    let highlightColor: Color
    @ViewBuilder let content: () -> Content

    init(
        isHighlighted: Bool = false,
        highlightColor: Color = DesignSystem.Colors.tint,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isHighlighted = isHighlighted
        self.highlightColor = highlightColor
        self.content = content
    }

    var body: some View {
        content()
            .padding(DesignSystem.Dimensions.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusLG)
                    .fill(isHighlighted ? highlightColor.opacity(0.1) : DesignSystem.Colors.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusLG)
                    .strokeBorder(
                        isHighlighted ? highlightColor : Color.clear,
                        lineWidth: 2
                    )
            )
    }
}

// MARK: - Previews

#Preview("Default Card") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        OnyxCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Exercise Name")
                    .font(.onyxHeader)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text("3 sets • 10 reps")
                    .font(.onyxCaption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
        .padding()
    }
}

#Preview("Highlighted Card") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        OnyxCard(isHighlighted: true) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Current Exercise")
                    .font(.onyxHeader)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text("In progress")
                    .font(.onyxCaption)
                    .foregroundStyle(DesignSystem.Colors.tint)
            }
        }
        .padding()
    }
}
