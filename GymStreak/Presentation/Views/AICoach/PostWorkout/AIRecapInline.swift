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

        case .preparing:
            surfaceView(text: "", isStreaming: true)

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

    /// Cross-dissolves skeleton bars into the streamed text, the shape
    /// `CoachDeepDiveSurface` and `CoachWorkoutAnalysisSurface` already use.
    ///
    /// Both are drawn in a `ZStack` with a `minHeight` rather than swapped, so the card
    /// reserves its height from the first frame and the sheet does not grow under the
    /// reader's thumb as tokens arrive — the same reservation `PeriodRecapView`'s
    /// `sectionCardSlot` makes.
    @ViewBuilder
    private func surfaceView(text: String, isStreaming: Bool) -> some View {
        AISurface(
            isStreaming: isStreaming,
            onRegenerate: isStreaming ? nil : onRegenerate
        ) {
            ZStack(alignment: .topLeading) {
                AISkeletonLines(count: 3)
                    .opacity(text.isEmpty ? 1 : 0)

                StreamingTextView(
                    text: text,
                    isStreaming: isStreaming
                )
                .opacity(text.isEmpty ? 0 : 1)
            }
            .frame(minHeight: skeletonHeight, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.25), value: text.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    /// Three lines for the two-to-three sentences the prompt asks for.
    /// 3 × 12 pt bars + 2 × 8 pt spacing.
    private var skeletonHeight: CGFloat { 52 }
}
