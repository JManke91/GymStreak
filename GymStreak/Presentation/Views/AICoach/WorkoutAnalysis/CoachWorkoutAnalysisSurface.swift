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
/// Renders the structured analysis (headline → per-exercise trend rows →
/// closing observation). While preparing/streaming, missing fields show
/// shimmer skeleton bars inside the same layout so the card never jumps.
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

        case .preparing:
            generatingSurface(content: WorkoutAnalysisContent())

        case .streaming(let content):
            generatingSurface(content: content)

        case .success(let content, _):
            successSurface(content: content)

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

    // MARK: - Preparing / streaming variant

    private func generatingSurface(content: WorkoutAnalysisContent) -> some View {
        AISurface(
            isStreaming: true,
            showFooter: false,
            headerLabel: "COACH · ANALYSE"
        ) {
            analysisBody(content: content, isStreaming: true)
        }
        .frame(minHeight: 200, alignment: .topLeading)
    }

    // MARK: - Success variant

    private func successSurface(content: WorkoutAnalysisContent) -> some View {
        AISurface(
            isStreaming: false,
            showFooter: true,
            headerLabel: "COACH · ANALYSE",
            onRegenerate: onRegenerate
        ) {
            analysisBody(content: content, isStreaming: false)
        }
        .frame(minHeight: 200, alignment: .topLeading)
    }

    // MARK: - Structured body

    private func analysisBody(content: WorkoutAnalysisContent, isStreaming: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            headlineSlot(content.headline)
            highlightsSlot(content.highlights, isStreaming: isStreaming)
            closingSlot(content.closingObservation, isStreaming: isStreaming)
        }
        .animation(.easeOut(duration: 0.25), value: content)
    }

    // MARK: - Headline

    @ViewBuilder
    private func headlineSlot(_ headline: String) -> some View {
        if headline.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                AISkeletonBar(height: 14)
                AISkeletonBar(width: 180, height: 14)
            }
        } else {
            Text(headline)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Highlights

    @ViewBuilder
    private func highlightsSlot(_ highlights: [WorkoutAnalysisContent.Highlight], isStreaming: Bool) -> some View {
        if highlights.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                skeletonRow(nameWidth: 110)
                skeletonRow(nameWidth: 140)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(highlights) { highlight in
                    highlightRow(highlight)
                }
            }
        }
    }

    private func highlightRow(_ highlight: WorkoutAnalysisContent.Highlight) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            trendIcon(highlight.trend)

            VStack(alignment: .leading, spacing: 2) {
                if highlight.exerciseName.isEmpty {
                    AISkeletonBar(width: 120, height: 12)
                } else {
                    Text(highlight.exerciseName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                }

                if highlight.detail.isEmpty {
                    AISkeletonBar(width: 190, height: 10)
                } else {
                    Text(highlight.detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.68))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func trendIcon(_ trend: WorkoutAnalysisTrend?) -> some View {
        Image(systemName: trendSymbol(trend))
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(trendColor(trend))
            .frame(width: 22, height: 22)
            .background(
                Circle().fill(trendColor(trend).opacity(0.12))
            )
            .accessibilityHidden(true)
    }

    private func trendSymbol(_ trend: WorkoutAnalysisTrend?) -> String {
        switch trend {
        case .improved: "arrow.up.right"
        case .declined: "arrow.down.right"
        case .unchanged: "equal"
        case .mixed: "arrow.up.arrow.down"
        case .new: "plus"
        case nil: "ellipsis"
        }
    }

    private func trendColor(_ trend: WorkoutAnalysisTrend?) -> Color {
        switch trend {
        case .improved: AICoachTheme.accent
        case .declined: AICoachTheme.warningAccent
        case .mixed: Color.white.opacity(0.7)
        case .unchanged, .new, nil: Color.white.opacity(0.55)
        }
    }

    private func skeletonRow(nameWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 6) {
                AISkeletonBar(width: nameWidth, height: 12)
                AISkeletonBar(width: nameWidth + 70, height: 10)
            }
        }
    }

    // MARK: - Closing observation

    @ViewBuilder
    private func closingSlot(_ closing: String, isStreaming: Bool) -> some View {
        if closing.isEmpty {
            if isStreaming {
                AISkeletonBar(width: 220, height: 12)
            }
        } else {
            Text(closing)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.6))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Previews

#Preview("Preparing") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()
        CoachWorkoutAnalysisSurface(
            state: .preparing,
            routineName: "Push Day",
            onRegenerate: {}
        )
        .padding(16)
    }
}

#Preview("Streaming") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()
        CoachWorkoutAnalysisSurface(
            state: .streaming(content: WorkoutAnalysisContent(
                headline: "Du hast 150 kg mehr Volumen bewegt als in der letzten Einheit.",
                highlights: [
                    .init(id: 0, exerciseName: "Bench Press", trend: .improved, detail: "2,5 kg mehr bei jedem Satz."),
                    .init(id: 1, exerciseName: "Chin Up", trend: nil, detail: ""),
                ]
            )),
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
                content: WorkoutAnalysisContent(
                    headline: "Du hast 150 kg mehr Volumen bewegt als in der letzten Einheit.",
                    highlights: [
                        .init(id: 0, exerciseName: "Bench Press", trend: .improved, detail: "2,5 kg mehr bei jedem Satz."),
                        .init(id: 1, exerciseName: "Chin Up", trend: .improved, detail: "3 Wiederholungen mehr insgesamt."),
                        .init(id: 2, exerciseName: "Biceps Curl", trend: .declined, detail: "2 Wiederholungen weniger insgesamt."),
                    ],
                    closingObservation: "Insgesamt eine solide Steigerung bei den Hauptübungen."
                ),
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
