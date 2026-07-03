//
//  AIRecapInline.swift
//  GymStreak
//
//  Inline renderer for the post-workout AI recap in SaveWorkoutView.
//  Handles the three visible states: streaming/success (AISurface),
//  unavailable, insufficient-data, and error (FallbackHintLine).
//

import SwiftUI

/// Renders the appropriate UI for each `PostWorkoutRecapViewModel.RecapState`.
///
/// Designed to be embedded inside a Form `Section` with `.listRowBackground(Color.clear)`
/// and `.listRowInsets(.init())` so `AISurface` renders edge-to-edge within its row.
struct AIRecapInline: View {

    // MARK: - Props

    let state: PostWorkoutRecapViewModel.RecapState
    let onRegenerate: () -> Void

    // MARK: - Body

    var body: some View {
        switch state {
        case .idle:
            // Blank placeholder — nothing visible before generation starts
            Color.clear.frame(height: 0)

        case .streaming(let text):
            surfaceView(text: text, isStreaming: true)

        case .success(let text):
            surfaceView(text: text, isStreaming: false)

        case .unavailable:
            FallbackHintLine(
                text: "ai_coach.post_workout.unavailable".localized,
                action: (
                    label: "ai_coach.post_workout.unavailable_action".localized,
                    onTap: {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                )
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 4)

        case .insufficientData:
            FallbackHintLine(
                text: "ai_coach.post_workout.insufficient_data".localized
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 4)

        case .error:
            FallbackHintLine(
                text: "ai_coach.post_workout.error".localized,
                action: (
                    label: "ai_coach.post_workout.error_action".localized,
                    onTap: onRegenerate
                )
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Surface helper

    @ViewBuilder
    private func surfaceView(text: String, isStreaming: Bool) -> some View {
        AISurface(
            isStreaming: isStreaming,
            onRegenerate: isStreaming ? nil : onRegenerate
        ) {
            StreamingTextView(
                text: text,
                isStreaming: isStreaming
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}
