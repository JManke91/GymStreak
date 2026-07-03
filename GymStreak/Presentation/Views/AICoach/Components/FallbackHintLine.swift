//
//  FallbackHintLine.swift
//  GymStreak
//
//  Dashed-border 1-line card for the post-workout "unavailable" and
//  "insufficient data" fallback states. Matches the `FallbackLine` component
//  in the design HTML.
//

import SwiftUI

/// A compact dashed-border hint row for AI Coach unavailable / insufficient-data states.
///
/// Shows a dimmed sparkle icon, a short message, and an optional tappable action label
/// (e.g. "Einstellungen" that deep-links to Settings).
struct FallbackHintLine: View {

    // MARK: - Props

    let text: String
    /// Optional inline action. `label` appears as a tinted tappable button on the trailing edge.
    var action: (label: String, onTap: () -> Void)? = nil

    // MARK: - Body

    var body: some View {
        HStack(spacing: 10) {
            // Dimmed sparkle
            AISparkleView(size: 14, color: Color.white.opacity(0.35))

            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(0.55))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let action {
                Button(action: action.onTap) {
                    Text(action.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AICoachTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Color.white.opacity(0.10))
        )
    }
}

// MARK: - Previews

#Preview("Unavailable — with action") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        FallbackHintLine(
            text: "ai_coach.fallback_unavailable".localized,
            action: (
                label: "ai_coach.fallback_action_settings".localized,
                onTap: {}
            )
        )
        .padding()
    }
}

#Preview("Insufficient data — no action") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        FallbackHintLine(
            text: "ai_coach.fallback_insufficient".localized
        )
        .padding()
    }
}
