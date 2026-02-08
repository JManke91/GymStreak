//
//  OnyxEmptyState.swift
//  GymStreak
//
//  Empty state view with icon, title, description, and action for the Onyx Design System
//

import SwiftUI

/// An empty state view styled with Onyx Design System
struct OnyxEmptyState: View {
    let icon: String
    let title: String
    let description: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        icon: String,
        title: String,
        description: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            VStack(spacing: DesignSystem.Spacing.sm) {
                Text(title)
                    .font(.onyxTitle2)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                Text(description)
                    .font(.onyxBody)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle = actionTitle, let action = action {
                OnyxButton(actionTitle, style: .primary, action: action)
                    .padding(.horizontal, DesignSystem.Spacing.xxl)
            }
        }
        .padding(DesignSystem.Spacing.xl)
    }
}

// MARK: - Previews

#Preview("Empty State with Action") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        OnyxEmptyState(
            icon: "dumbbell",
            title: "No Exercises",
            description: "Add your first exercise to get started with your workout routine.",
            actionTitle: "Add Exercise"
        ) {
            print("Add exercise tapped")
        }
    }
}

#Preview("Empty State without Action") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        OnyxEmptyState(
            icon: "clock.fill",
            title: "No Workout History",
            description: "Complete a workout to see your history here."
        )
    }
}
