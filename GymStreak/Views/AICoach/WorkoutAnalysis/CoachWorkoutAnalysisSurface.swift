//
//  CoachWorkoutAnalysisSurface.swift
//  GymStreak
//
//  Expanded AI Coach surface rendered once the user taps "Coach fragen"
//  in WorkoutDetailView. Handles all `AnalysisState` variants.
//

import SwiftUI

/// Expanded AI Coach surface for workout detail analysis.
///
/// Shown whenever `WorkoutAnalysisViewModel.state != .idle`.
/// Delegates streaming/static rendering to `AISurface` + `StreamingTextView`.
struct CoachWorkoutAnalysisSurface: View {

    // MARK: - Props

    let state: WorkoutAnalysisViewModel.AnalysisState
    /// Display name of the routine — appears in the surface header.
    let routineName: String
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
                text: "ai_coach.workout_analysis.unavailable".localized
            )

        case .insufficientData:
            FallbackHintLine(
                text: "ai_coach.workout_analysis.insufficient_data".localized
            )

        case .error:
            FallbackHintLine(
                text: "ai_coach.workout_analysis.error".localized,
                action: (
                    label: "ai_coach.workout_analysis.error_retry".localized,
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
            headerLabel: "COACH · ANALYSE"
        ) {
            narrativeBody(text: text, isStreaming: true)
        }
        .frame(minHeight: 200, alignment: .topLeading)
    }

    // MARK: - Success variant

    private func successSurface(text: String) -> some View {
        AISurface(
            isStreaming: false,
            showFooter: true,
            headerLabel: "COACH · ANALYSE",
            onRegenerate: onRegenerate
        ) {
            narrativeBody(text: text, isStreaming: false)
        }
        .frame(minHeight: 200, alignment: .topLeading)
    }

    // MARK: - Narrative body

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
        CoachWorkoutAnalysisSurface(
            state: .streaming(text: "Dein Push-Tag zeigt insgesamt ein Volumen von 2.1t — das sind 150 kg mehr als beim letzten Mal."),
            routineName: "Push Day",
            onRegenerate: {}
        )
        .padding(16)
    }
}

#Preview("Success") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()
        CoachWorkoutAnalysisSurface(
            state: .success(
                text: "Dein Push-Tag zeigt insgesamt ein Volumen von 2.1t — das sind 150 kg mehr als beim letzten Mal.\n\nBeim Bankdrücken hast du bei allen drei Sätzen das Gewicht um 2.5 kg gesteigert. Die Wiederholungen beim Seitheben sind dagegen gleich geblieben.\n\nInsgesamt ein solider Fortschritt bei den Hauptübungen, während die Isolationsarbeit stabil bleibt.",
                isCached: false
            ),
            routineName: "Push Day",
            onRegenerate: {}
        )
        .padding(16)
    }
}

#Preview("Insufficient Data") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()
        CoachWorkoutAnalysisSurface(
            state: .insufficientData,
            routineName: "Push Day",
            onRegenerate: {}
        )
        .padding(16)
    }
}
