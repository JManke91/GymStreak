//
//  CoachDeepDiveSurface.swift
//  GymStreak
//
//  Expanded AI Coach surface rendered once the user taps "Coach fragen".
//  Handles all `DeepDiveState` variants: streaming, success, unavailable,
//  insufficientData, and error.
//

import SwiftUI

/// Expanded AI Coach surface for exercise deep-dive analysis.
///
/// Shown whenever `ExerciseDeepDiveViewModel.state != .idle`.
/// Delegates streaming/static rendering to `AISurface` + `StreamingTextView`.
struct CoachDeepDiveSurface: View {

    // MARK: - Props

    let state: ExerciseDeepDiveViewModel.DeepDiveState
    /// Display name of the exercise — appears in the surface header.
    let exerciseName: String
    let onRegenerate: () -> Void

    // MARK: - Body

    var body: some View {
        switch state {
        case .idle:
            EmptyView()

        case .streaming(let text):
            streamingSurface(text: text)

        case .success(let text, _):
            successSurface(text: text)

        case .unavailable:
            FallbackHintLine(
                text: "ai_coach.deep_dive.unavailable".localized
            )

        case .insufficientData:
            FallbackHintLine(
                text: "ai_coach.deep_dive.insufficient_data".localized
            )

        case .error:
            FallbackHintLine(
                text: "ai_coach.deep_dive.error".localized,
                action: (
                    label: "ai_coach.deep_dive.error_retry".localized,
                    onTap: onRegenerate
                )
            )
        }
    }

    // MARK: - Streaming variant

    private func streamingSurface(text: String) -> some View {
        AISurface(
            isStreaming: true,
            showFooter: false,
            headerLabel: "COACH · \(exerciseName.uppercased())"
        ) {
            narrativeBody(text: text, isStreaming: true)
        }
        .frame(minHeight: 260, alignment: .topLeading)
    }

    // MARK: - Success variant

    private func successSurface(text: String) -> some View {
        AISurface(
            isStreaming: false,
            showFooter: true,
            headerLabel: "COACH · \(exerciseName.uppercased())",
            onRegenerate: onRegenerate
        ) {
            narrativeBody(text: text, isStreaming: false)
        }
        .frame(minHeight: 260, alignment: .topLeading)
    }

    // MARK: - Narrative body

    /// Renders the full narrative as a single `StreamingTextView`.
    /// SwiftUI's `Text` renders `\n\n` natively as a paragraph break, so
    /// splitting into multiple views is unnecessary and caused layout growth
    /// as double-newline separators appeared mid-stream.
    private func narrativeBody(text: String, isStreaming: Bool) -> some View {
        StreamingTextView(
            text: text,
            isStreaming: isStreaming,
            font: .system(size: 14),
            color: .white.opacity(0.88),
            lineSpacing: 4
        )
    }
}

// MARK: - Previews

#Preview("Streaming") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()
        CoachDeepDiveSurface(
            state: .streaming(text: "Du hast deine Curl-Kraft in den letzten sechs Monaten deutlich gesteigert."),
            exerciseName: "Bizeps Curl",
            onRegenerate: {}
        )
        .padding(16)
    }
}

#Preview("Success") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()
        CoachDeepDiveSurface(
            state: .success(
                text: "Deine Curl-Progression zeigt einen konstanten Aufwärtstrend über 8 Monate.\n\nDein stärkster Zeitraum war Februar bis April mit +4 kg geschätztem 1RM.\n\nDerzeit befindest du dich in einem Plateau — die Frequenz ist leicht zurückgegangen.",
                isCached: false
            ),
            exerciseName: "Bizeps Curl",
            onRegenerate: {}
        )
        .padding(16)
    }
}

#Preview("Insufficient Data") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()
        CoachDeepDiveSurface(
            state: .insufficientData,
            exerciseName: "Bizeps Curl",
            onRegenerate: {}
        )
        .padding(16)
    }
}

#Preview("Error") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()
        CoachDeepDiveSurface(
            state: .error,
            exerciseName: "Bizeps Curl",
            onRegenerate: {}
        )
        .padding(16)
    }
}
