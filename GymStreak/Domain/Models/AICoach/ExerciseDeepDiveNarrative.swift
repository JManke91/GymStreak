//
//  ExerciseDeepDiveNarrative.swift
//  GymStreak
//

import Foundation

/// One exercise deep-dive as the screen renders it and the cache stores it: the
/// paragraphs the model wrote, plus the one sentence Swift composed.
///
/// **`peakSentence` is not generated, and the model never receives the facts behind it.**
/// The peak used to travel into the prompt as labelled figures — `Weight: 20,0 kg × 6`,
/// `When: August 2026` — and on a device check the model wrote *"erreicht am 20.08.2026"*:
/// a day that exists nowhere in the input, its "20" lifted from the `20,0 kg` in the
/// adjacent clause. A month is a date a language model can make more precise, so the month
/// no longer reaches one. `ExerciseDeepDiveInput.peakSentence` composes the finished
/// sentence instead, `CoachDeepDiveSurface` renders it, and this type carries it through
/// the cache so a re-read shows it without re-walking history.
///
/// Same move as the variant label (`DeepDiveUsage`), which is the only grounding fix on
/// this surface that has held: nothing can mangle a string it never receives.
struct ExerciseDeepDiveNarrative: Codable, Equatable, Sendable {

    /// Paragraph 1 — how much training the narrative covers, and over which period.
    var workload: String
    /// Paragraph 2 — the progression. `nil` for a blended view, which has none.
    var progression: String?
    /// Paragraph 3 — where the reader stands (single variant), or what a progression
    /// would need (blended).
    var closing: String
    /// The all-time peak, composed in Swift. Never generated, never streamed.
    var peakSentence: String

    init(
        workload: String = "",
        progression: String? = nil,
        closing: String = "",
        peakSentence: String = ""
    ) {
        self.workload = workload
        self.progression = progression
        self.closing = closing
        self.peakSentence = peakSentence
    }

    /// - Parameter statesProgression: `false` for a blended view, where the progression
    ///   paragraph is dropped whatever the model returned. The instructions and the
    ///   field's `@Guide` both tell it to omit that field; this is the half that does not
    ///   depend on it obeying.
    init(output: ExerciseDeepDiveOutput, peakSentence: String, statesProgression: Bool) {
        self.init(
            workload: output.workload,
            progression: statesProgression ? output.progression : nil,
            closing: output.closing,
            peakSentence: peakSentence
        )
    }

    /// Assembled from a streaming snapshot, so the surface fills paragraph by paragraph
    /// instead of waiting for the whole narrative — the shape
    /// `CoachWorkoutAnalysisSurface` already uses.
    init(
        partial: ExerciseDeepDiveOutput.PartiallyGenerated,
        peakSentence: String,
        statesProgression: Bool
    ) {
        self.init(
            workload: partial.workload ?? "",
            progression: statesProgression ? (partial.progression ?? nil) : nil,
            closing: partial.closing ?? "",
            peakSentence: peakSentence
        )
    }
}
