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
    /// The usage the narrative describes, exactly as the picker names it
    /// (`ExerciseProgressViewModel.selectedUsageLabel` — "Alle Varianten" for the combined
    /// view). **`nil` when the screen offers no variant menu**: on an exercise trained
    /// exactly one way there is nothing to choose between, and a caption reading "Alle
    /// Varianten" would name a concept that screen never introduces.
    let usageLabel: String?
    let onRegenerate: () -> Void

    // MARK: - Body

    var body: some View {
        switch state {
        case .idle:
            EmptyView()

        case .preparing:
            streamingSurface(text: "")

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
            if text.isEmpty {
                skeletonBody
            } else {
                narrativeBody(text: text, isStreaming: true)
            }
        }
        .frame(minHeight: 260, alignment: .topLeading)
    }

    /// Placeholder shown between tapping "Ask the Coach" and the first token,
    /// so the surface never sits visually empty.
    private var skeletonBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            AISkeletonBar(height: 12)
            AISkeletonBar(height: 12)
            AISkeletonBar(width: 200, height: 12)
            Spacer(minLength: 0)
        }
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
        VStack(alignment: .leading, spacing: 8) {
            scopeCaption
            StreamingTextView(
                text: text,
                isStreaming: isStreaming,
                font: .system(size: 14),
                color: .white.opacity(0.88),
                lineSpacing: 4
            )
        }
    }

    /// Which body of work the narrative below describes: the usage, and the fact that it
    /// is measured over the user's whole history for it.
    ///
    /// **Rendered, not narrated.** Both facts used to depend on the on-device model
    /// getting them right, and it did not: asked to name the variant it turned
    /// `4–6 Wdh. · Pull` into "die 4-6-Woche-Biceps-Curls-Variante" — expanding *Wdh.*
    /// (Wiederholungen) into *Woche* — and it never mentioned the period at all, so a
    /// narrative computed over all time sat under a chart showing one month with nothing
    /// to say they differed. A label the user must be able to trust does not go through a
    /// language model; the prompt now forbids restating it (see
    /// `ExerciseDeepDiveInstructions`).
    ///
    /// The all-time scope is deliberate and is **not** the timeframe pill: a deep-dive
    /// over one week has nothing to say, and re-generating per window would spend a free
    /// user's monthly allowance on every pill tap (`docs/ai-coach.md` §3).
    private var scopeCaption: some View {
        Text(captionText)
            .font(.system(size: 11))
            .foregroundStyle(Color.white.opacity(0.45))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Two forms, because the scope has to read as a sentence fragment in both languages:
    /// appended to a variant it is lower-case ("… · gesamte Historie"), standing alone it
    /// leads ("Gesamte Historie").
    private var captionText: String {
        guard let usageLabel else {
            return "ai_coach.deep_dive.scope.all_time_only".localized
        }
        return "\(usageLabel) · \("ai_coach.deep_dive.scope.all_time".localized)"
    }
}

// MARK: - Previews

#Preview("Streaming") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()
        CoachDeepDiveSurface(
            state: .streaming(text: "Du hast deine Curl-Kraft in den letzten sechs Monaten deutlich gesteigert."),
            exerciseName: "Bizeps Curl",
            usageLabel: "4–6 Wdh. · Pull",
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
            usageLabel: "4–6 Wdh. · Pull",
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
            usageLabel: "4–6 Wdh. · Pull",
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
            usageLabel: "4–6 Wdh. · Pull",
            onRegenerate: {}
        )
        .padding(16)
    }
}
