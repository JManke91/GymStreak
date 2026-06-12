//
//  CoachWorkoutAnalysisButton.swift
//  GymStreak
//
//  "Coach fragen" affordance displayed in WorkoutDetailView
//  before the user initiates the workout analysis generation.
//

import SwiftUI

/// Full-width button that invites the user to ask the AI Coach for
/// a comparison analysis of this workout vs. the previous session
/// of the same routine.
///
/// Tapping it triggers `onTap`, which should start
/// `WorkoutAnalysisViewModel.generate(...)`.
struct CoachWorkoutAnalysisButton: View {

    // MARK: - Props

    /// Display name of the routine, injected into the subtitle.
    let routineName: String
    let onTap: () -> Void

    // MARK: - Body

    var body: some View {
        Button(action: {
            HapticManager.shared.light()
            onTap()
        }) {
            HStack(spacing: 12) {
                AISparkleView(size: 20, glow: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("ai_coach.workout_analysis.button_title".localized)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)

                    Text(String(format: "ai_coach.workout_analysis.button_subtitle".localized, routineName))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(buttonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DesignSystem.Colors.tint.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(format: "ai_coach.workout_analysis.button_accessibility".localized, routineName))
    }

    // MARK: - Background

    private var buttonBackground: some View {
        LinearGradient(
            colors: [
                DesignSystem.Colors.tint.opacity(0.12),
                DesignSystem.Colors.tint.opacity(0.04),
            ],
            startPoint: UnitPoint(x: 0.15, y: 0.0),
            endPoint: UnitPoint(x: 0.85, y: 1.0)
        )
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()
        CoachWorkoutAnalysisButton(routineName: "Push Day") { }
            .padding(16)
    }
}
