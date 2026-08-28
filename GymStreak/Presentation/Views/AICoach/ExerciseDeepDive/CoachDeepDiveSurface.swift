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
            streamingSurface(narrative: ExerciseDeepDiveNarrative())

        case .streaming(let narrative):
            streamingSurface(narrative: narrative)

        case .success(let narrative, _):
            successSurface(narrative: narrative)

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

    private func streamingSurface(narrative: ExerciseDeepDiveNarrative) -> some View {
        AISurface(
            isStreaming: true,
            showFooter: false,
            headerLabel: "COACH · \(exerciseName.uppercased())"
        ) {
            narrativeBody(narrative: narrative, isStreaming: true)
        }
        .frame(minHeight: 260, alignment: .topLeading)
    }

    // MARK: - Success variant

    private func successSurface(narrative: ExerciseDeepDiveNarrative) -> some View {
        AISurface(
            isStreaming: false,
            showFooter: true,
            headerLabel: "COACH · \(exerciseName.uppercased())",
            onRegenerate: onRegenerate
        ) {
            narrativeBody(narrative: narrative, isStreaming: false)
        }
        .frame(minHeight: 260, alignment: .topLeading)
    }

    // MARK: - Narrative body

    /// One slot per paragraph, each filling independently as the stream delivers its
    /// field — the shape `CoachWorkoutAnalysisSurface` already uses. A paragraph that has
    /// not arrived yet shows skeleton bars inside the same layout, so the card neither
    /// sits visually empty between the tap and the first token nor jumps as fields land.
    ///
    /// The paragraphs used to be one `String` split on `\n\n`, which is why the surface
    /// once rendered a single `StreamingTextView`: the model was asked in prose for "3 to
    /// 4 short paragraphs" and returned one undivided block on every device check. The
    /// shape now lives in `ExerciseDeepDiveOutput`'s fields instead.
    private func narrativeBody(narrative: ExerciseDeepDiveNarrative, isStreaming: Bool) -> some View {
        let progression = narrative.progression ?? ""
        // The blinking cursor belongs to the paragraph being written — the last one that
        // has any text — so three slots never blink in three places at once. A fixed
        // three-element literal, not a collection that grows with the user's data.
        let cursorSlot: Int? = isStreaming
            ? [narrative.workload, progression, narrative.closing].lastIndex { !$0.isEmpty }
            : nil

        return VStack(alignment: .leading, spacing: 12) {
            scopeCaption
            paragraphSlot(narrative.workload, showsCursor: cursorSlot == 0, placeholderLines: isStreaming ? 3 : 0)
            // No placeholder for the progression: it is legitimately absent on a blended
            // view, so reserving a slot would promise a paragraph that is never coming.
            // The two slots around it already keep the card from sitting empty.
            paragraphSlot(progression, showsCursor: cursorSlot == 1, placeholderLines: 0)
            paragraphSlot(narrative.closing, showsCursor: cursorSlot == 2, placeholderLines: isStreaming ? 2 : 0)
            peakLine(narrative.peakSentence)
        }
        // Keyed on which slots are filled, never on the narrative itself: FoundationModels
        // snapshots arrive at ~30 Hz, so `value: narrative` would open an animated
        // transaction over the whole stack on every token. `StreamingTextView` suppresses
        // exactly that for its own `Text` (`.animation(nil)` + `disablesAnimations`), but
        // that does not cover this `VStack`'s layout, the skeleton bars or the peak line.
        // What is worth animating is the skeleton→text swap, which happens three times.
        .animation(
            .easeOut(duration: 0.25),
            value: [narrative.workload.isEmpty, (narrative.progression ?? "").isEmpty, narrative.closing.isEmpty]
        )
    }

    /// A generated paragraph, or shimmer bars while the field is still empty and one is
    /// worth reserving. An empty field with no placeholder renders nothing at all, so a
    /// finished narrative never leaves a bar shimmering forever.
    @ViewBuilder
    private func paragraphSlot(_ text: String, showsCursor: Bool, placeholderLines: Int) -> some View {
        if text.isEmpty {
            if placeholderLines > 0 { skeletonLines(placeholderLines) }
        } else {
            StreamingTextView(
                text: text,
                isStreaming: showsCursor,
                font: .system(size: 14),
                color: .white.opacity(0.88),
                lineSpacing: 4
            )
        }
    }

    private func skeletonLines(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                AISkeletonBar(width: index == count - 1 ? 200 : nil, height: 12)
            }
        }
    }

    /// The all-time peak, composed in Swift and never generated — see
    /// `ExerciseDeepDiveInput.peakSentence`. Rendered in the caption's weight so it reads
    /// as a fact of the record rather than as part of the coach's prose, and rendered
    /// from the first frame because it does not have to be waited for.
    @ViewBuilder
    private func peakLine(_ sentence: String) -> some View {
        if !sentence.isEmpty {
            Text(sentence)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.6))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
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

private let previewPeak = "Bestwert: 26,0 kg × 5 Wdh. (geschätztes 1RM 30,3 kg), April 1970."

#Preview("Streaming") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()
        CoachDeepDiveSurface(
            state: .streaming(narrative: ExerciseDeepDiveNarrative(
                workload: "Du hast diese Variante in 15 Sitzungen trainiert, verteilt über Juli 2026 – August 2026.",
                closing: "",
                peakSentence: previewPeak
            )),
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
                narrative: ExerciseDeepDiveNarrative(
                    workload: "Du hast diese Variante in 15 Sitzungen trainiert, verteilt über Juli 2026 – August 2026.",
                    progression: "Dein geschätztes 1RM ist in diesem Zeitraum um 4,0 kg gestiegen, das sind +18 %. Der stärkste Abschnitt lag zwischen Juli 2026 und August 2026.",
                    closing: "Aktuell befindest du dich in einem Plateau. In diesem Abschnitt trainierst du 1,5 Mal pro Woche, im stärksten Abschnitt waren es 2,0.",
                    peakSentence: previewPeak
                ),
                isCached: false
            ),
            exerciseName: "Bizeps Curl",
            usageLabel: "4–6 Wdh. · Pull",
            onRegenerate: {}
        )
        .padding(16)
    }
}

/// The blended view: no progression paragraph at all, and none reserved for it.
#Preview("Success — blended") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()
        CoachDeepDiveSurface(
            state: .success(
                narrative: ExerciseDeepDiveNarrative(
                    workload: "Du hast diese Übung in 21 Sitzungen trainiert, verteilt über Juli 2026 – August 2026, in 3 verschiedenen Varianten.",
                    closing: "Diese Varianten verfolgen unterschiedliche Ziele. Eine Progression lässt sich nur für eine einzelne ausgewählte Variante auswerten.",
                    peakSentence: previewPeak
                ),
                isCached: false
            ),
            exerciseName: "Bizeps Curl",
            usageLabel: "Alle Varianten",
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
